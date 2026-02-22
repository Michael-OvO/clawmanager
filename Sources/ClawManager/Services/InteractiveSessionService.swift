import Foundation

actor InteractiveSessionService {

    // MARK: - State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?

    private var currentSessionId: String?
    private var currentWorkspacePath: String?
    private var eventContinuation: AsyncStream<InteractiveEvent>.Continuation?

    // Streaming accumulator
    private var currentMessage: LiveMessage?
    private var currentBlockType: String?

    // Diagnostic log file for debugging connection issues
    private static let logPath = "/tmp/clawmanager_interactive.log"

    private nonisolated static func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    // MARK: - Public API

    /// Create a persistent event stream. Multiple CLI processes can feed into
    /// the same stream sequentially. The stream only ends when disconnect() is called.
    func openStream(sessionId: String, workspacePath: String) -> AsyncStream<InteractiveEvent> {
        // Tear down any previous connection
        teardownProcess()
        eventContinuation?.finish()

        currentSessionId = sessionId
        currentWorkspacePath = workspacePath
        currentMessage = nil

        let (stream, continuation) = AsyncStream<InteractiveEvent>.makeStream()
        self.eventContinuation = continuation

        Self.log("=== OPEN STREAM sessionId=\(sessionId) ===")
        return stream
    }

    /// Spawn a CLI process to handle one or more turns.
    /// If `initialMessage` is provided, it's piped to stdin immediately so
    /// the CLI has work to do (preventing instant exit on completed sessions).
    func ensureProcess(initialMessage: String? = nil) {
        guard let sessionId = currentSessionId,
              let workspacePath = currentWorkspacePath else {
            Self.log("ERROR: ensureProcess called without session context")
            return
        }

        // If we already have a running process, nothing to do
        if let proc = process, proc.isRunning {
            Self.log("ensureProcess: already running PID=\(proc.processIdentifier)")
            return
        }

        // Clean up any dead process state
        teardownProcess()

        Self.log("=== SPAWN PROCESS sessionId=\(sessionId) ===")

        guard let claudePath = Self.findClaudeBinary() else {
            Self.log("ERROR: Claude CLI not found")
            emit(.connectionChanged(.error("Claude CLI not found")))
            return
        }
        Self.log("Found claude at: \(claudePath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = [
            "-p",
            "--resume", sessionId,
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--include-partial-messages",
            "--dangerously-skip-permissions",
            "--verbose"
        ]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

        // Ensure PATH includes node bin dir so claude can find its deps
        var env = ProcessInfo.processInfo.environment
        let nodeBinDir = (claudePath as NSString).deletingLastPathComponent
        if let path = env["PATH"] {
            env["PATH"] = "\(nodeBinDir):\(path)"
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        proc.terminationHandler = { [weak self] p in
            Task { [weak self] in
                await self?.handleTermination(exitCode: p.terminationStatus)
            }
        }

        Self.log("Launching: \(claudePath) \(proc.arguments?.joined(separator: " ") ?? "")")
        do {
            try proc.run()
            Self.log("Process launched, PID=\(proc.processIdentifier)")
        } catch {
            Self.log("ERROR: Launch failed: \(error.localizedDescription)")
            emit(.connectionChanged(.error("Launch failed: \(error.localizedDescription)")))
            return
        }

        // If we have an initial message, write it to stdin immediately so
        // the CLI has a user turn to process (prevents instant exit).
        if let message = initialMessage {
            Self.log("Writing initial message to stdin")
            writeUserMessage(message)
        }

        // Read stdout on a DETACHED task — NOT on the actor.
        // FileHandle.availableData is a blocking call.
        readTask = Task.detached { [weak self] in
            var buffer = Data()
            let newline = UInt8(ascii: "\n")

            while !Task.isCancelled {
                let data = stdout.fileHandleForReading.availableData
                guard !data.isEmpty else { break } // EOF

                buffer.append(data)

                // Process complete lines
                while let idx = buffer.firstIndex(of: newline) {
                    let lineData = buffer[buffer.startIndex..<idx]
                    buffer = Data(buffer[buffer.index(after: idx)...])

                    if let line = String(data: lineData, encoding: .utf8),
                       !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        await self?.processLine(line)
                    }
                }
            }
            Self.log("readTask: EOF reached, loop ended")
        }

        // Read stderr and log it for diagnostics
        stderrDrainTask = Task.detached {
            while !Task.isCancelled {
                let data = stderr.fileHandleForReading.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    Self.log("STDERR: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }

    /// Send a user text message using the stream-json input format.
    /// Spawns a new CLI process if the current one isn't running.
    func sendMessage(_ text: String) {
        if process?.isRunning != true {
            Self.log("sendMessage: no running process, spawning with initial message")
            ensureProcess(initialMessage: text)
        } else {
            Self.log("sendMessage: writing to running process")
            writeUserMessage(text)
        }
    }

    /// Approve a pending tool call.
    func approveToolCall() {
        writeToStdin("y\n")
    }

    /// Reject a pending tool call.
    func rejectToolCall() {
        writeToStdin("n\n")
    }

    /// Disconnect: kill process and finish the event stream.
    func disconnect() {
        Self.log("=== DISCONNECT ===")
        teardownProcess()

        currentSessionId = nil
        currentWorkspacePath = nil
        currentMessage = nil

        eventContinuation?.finish()
        eventContinuation = nil
    }

    var isProcessAlive: Bool {
        process?.isRunning == true
    }

    // MARK: - Private Helpers

    private func teardownProcess() {
        readTask?.cancel()
        readTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
    }

    private func writeUserMessage(_ text: String) {
        let inputJson: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": text]
                ]
            ]
        ]
        writeJsonToStdin(inputJson)
    }

    // MARK: - Line Parsing (NDJSON from stream-json)

    private func processLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            Self.log("UNPARSEABLE LINE: \(String(line.prefix(200)))")
            return
        }

        // Log event type (truncate content for brevity)
        let subtype = json["subtype"] as? String
        let eventInfo = json["event"] as? [String: Any]
        let eventType = eventInfo?["type"] as? String
        Self.log("EVENT: type=\(type) subtype=\(subtype ?? "-") event=\(eventType ?? "-")")

        switch type {
        case "system":
            // System events (hook_started, hook_response, init) — informational only.
            // We don't gate connection state on these because connection
            // state is managed by SessionStore, not the service.
            break

        case "assistant":
            handleAssistantMessage(json)

        case "user":
            // Echoed user message — ignore
            break

        case "result":
            handleResult(json)

        case "stream_event":
            // Streaming events are wrapped: {"type":"stream_event","event":{...}}
            if let event = json["event"] as? [String: Any],
               let eventType = event["type"] as? String {
                handleStreamEvent(eventType: eventType, json: event)
            }

        default:
            break
        }
    }

    private func handleAssistantMessage(_ json: [String: Any]) {
        // Complete assistant message — finalize any streaming message
        if var msg = currentMessage {
            msg.isComplete = true

            // Extract full content from the complete message
            if let message = json["message"] as? [String: Any],
               let contentArray = message["content"] as? [[String: Any]] {
                var text = ""
                for block in contentArray {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let t = block["text"] as? String {
                        text += t
                    }
                }
                if !text.isEmpty {
                    msg.textAccumulator = text
                }
            }

            emit(.messageCompleted(msg))
            currentMessage = nil
        } else {
            // No streaming message accumulated — create from the complete message
            if let message = json["message"] as? [String: Any],
               let contentArray = message["content"] as? [[String: Any]] {
                var text = ""
                for block in contentArray {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let t = block["text"] as? String {
                        text += t
                    }
                }
                if !text.isEmpty {
                    let msg = LiveMessage(
                        id: (message["id"] as? String) ?? UUID().uuidString,
                        role: .assistant,
                        textAccumulator: text,
                        thinkingAccumulator: "",
                        toolCalls: [],
                        isComplete: true,
                        timestamp: Date()
                    )
                    emit(.messageCompleted(msg))
                }
            }
        }
    }

    private func handleResult(_ json: [String: Any]) {
        let isError = json["is_error"] as? Bool ?? false
        let result = json["result"] as? String
        let cost = json["total_cost_usd"] as? Double
        emit(.resultReceived(isError: isError, result: result, costUsd: cost))
    }

    private func handleStreamEvent(eventType: String, json: [String: Any]) {
        switch eventType {
        case "message_start":
            let messageInfo = json["message"] as? [String: Any]
            currentMessage = LiveMessage(
                id: (messageInfo?["id"] as? String) ?? UUID().uuidString,
                role: .assistant,
                textAccumulator: "",
                thinkingAccumulator: "",
                toolCalls: [],
                isComplete: false,
                timestamp: Date()
            )

        case "content_block_start":
            guard let contentBlock = json["content_block"] as? [String: Any],
                  let blockType = contentBlock["type"] as? String else { return }
            currentBlockType = blockType

            if blockType == "tool_use" {
                let toolName = contentBlock["name"] as? String ?? "Unknown"
                let toolId = contentBlock["id"] as? String ?? UUID().uuidString
                let toolCall = LiveToolCall(
                    id: toolId,
                    name: toolName,
                    inputJson: "",
                    isComplete: false,
                    result: nil,
                    isError: false
                )
                currentMessage?.toolCalls.append(toolCall)
                // Don't emit toolCallStarted here — inputJson is empty.
                // We emit at content_block_stop once the full input has streamed in.
            }

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return }

            switch deltaType {
            case "text_delta":
                if let text = delta["text"] as? String {
                    currentMessage?.textAccumulator += text
                    if let msg = currentMessage {
                        emit(.messageUpdated(msg))
                    }
                }
            case "thinking_delta":
                if let thinking = delta["thinking"] as? String {
                    currentMessage?.thinkingAccumulator += thinking
                    if let msg = currentMessage {
                        emit(.messageUpdated(msg))
                    }
                }
            case "input_json_delta":
                if let partial = delta["partial_json"] as? String,
                   let lastIdx = currentMessage?.toolCalls.indices.last {
                    currentMessage?.toolCalls[lastIdx].inputJson += partial
                }
            default:
                break
            }

        case "content_block_stop":
            if currentBlockType == "tool_use",
               let lastIdx = currentMessage?.toolCalls.indices.last {
                currentMessage?.toolCalls[lastIdx].isComplete = true
                // Emit toolCallStarted NOW with the full inputJson populated.
                // The CLI will pause here if it needs user approval for this tool.
                emit(.toolCallStarted(currentMessage!.toolCalls[lastIdx]))
            }
            currentBlockType = nil

        case "message_delta":
            // Contains stop_reason — message is about to complete
            break

        case "message_stop":
            if var msg = currentMessage {
                msg.isComplete = true
                emit(.messageCompleted(msg))
                currentMessage = nil
            }

        default:
            break
        }
    }

    // MARK: - Stdin Writing

    private func writeJsonToStdin(_ json: [String: Any]) {
        guard let proc = process, proc.isRunning,
              let jsonData = try? JSONSerialization.data(withJSONObject: json),
              var jsonString = String(data: jsonData, encoding: .utf8) else { return }
        jsonString += "\n"
        if let data = jsonString.data(using: .utf8) {
            stdinPipe?.fileHandleForWriting.write(data)
        }
    }

    private func writeToStdin(_ text: String) {
        guard let proc = process, proc.isRunning,
              let data = text.data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(data)
    }

    // MARK: - Process Lifecycle

    private func handleTermination(exitCode: Int32) {
        let reason = exitCode == 0 ? "Turn completed" : "Process exited (\(exitCode))"
        Self.log("TERMINATED: exitCode=\(exitCode) reason=\(reason)")

        // Clean up the dead process but DON'T finish the event continuation.
        // The continuation stays alive so the next spawned process can reuse it.
        // Only disconnect() finishes the continuation.
        readTask?.cancel()
        readTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil

        // Notify the store that the process ended so it can update UI
        // (e.g., hide the streaming indicator) but NOT change connection state.
        if exitCode != 0 {
            emit(.connectionChanged(.error(reason)))
        } else {
            emit(.processExited)
        }
    }

    private func emit(_ event: InteractiveEvent) {
        eventContinuation?.yield(event)
    }

    // MARK: - Claude Binary Discovery

    nonisolated static func findClaudeBinary() -> String? {
        let fm = FileManager.default

        // Check common install locations
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]

        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Check nvm installations
        let home = fm.homeDirectoryForCurrentUser.path
        let nvmDir = "\(home)/.nvm/versions/node"
        if let nodeDirs = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for nodeDir in nodeDirs.sorted().reversed() {
                let path = "\(nvmDir)/\(nodeDir)/bin/claude"
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        // Fallback: `which claude`
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, fm.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}

        return nil
    }
}
