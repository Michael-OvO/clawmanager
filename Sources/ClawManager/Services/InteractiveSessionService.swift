import Foundation

// MARK: - Interactive Session Service
//
// Manages a Claude CLI process via the stream-json + control protocol.
// Spawns `claude --resume <id>` with stdio flags, parses NDJSON events
// on stdout, and sends user messages / control responses on stdin.
//
// IMPORTANT: The stdout read loop runs entirely in a Task.detached
// context — never on the actor's executor. All parse methods are static
// to avoid accidentally blocking the actor with FileHandle.availableData.

actor InteractiveSessionService {

    // MARK: - Event Types

    enum Event: Sendable {
        case connected(sessionId: String, model: String?, permissionMode: String?)
        case streamText(String)
        case streamThinking(String)
        case toolUseStart(id: String, name: String)
        case permissionRequest(requestId: String, toolName: String, inputJSON: String)
        case messageComplete(ParsedMessage?)
        case result(durationMs: Int, costUSD: Double?)
        case error(String)
        case disconnected
    }

    // MARK: - State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var readTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?
    private(set) var connectedSessionId: String?
    var isConnected: Bool { process != nil && (process?.isRunning ?? false) }

    // MARK: - Connect

    /// Spawn a Claude CLI process and return a stream of events.
    /// The caller should iterate the stream to receive events.
    func connect(
        sessionId: String,
        workDir: String,
        permissionMode: String? = nil
    ) -> AsyncStream<Event> {
        disconnect()

        let (stream, cont) = AsyncStream<Event>.makeStream()
        self.continuation = cont

        guard let binaryPath = Self.findClaudeBinary() else {
            Diag.log(.error, .app, "Claude binary not found")
            cont.yield(.error("Claude binary not found"))
            cont.finish()
            return stream
        }

        var args = [
            "--resume", sessionId,
            "-p", "",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--permission-prompt-tool", "stdio",
            "--verbose",
            "--no-chrome",
            "--include-partial-messages"
        ]

        if let mode = permissionMode {
            args.append(contentsOf: ["--permission-mode", mode])
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: workDir)

        // Inherit environment for NVM/Homebrew PATH resolution
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            let extra = [
                "\(NSHomeDirectory())/.nvm/versions/node/v22.18.0/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
            env["PATH"] = (extra + [path]).joined(separator: ":")
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.stdinPipe = stdin
        self.process = proc
        self.connectedSessionId = sessionId

        // Termination handler
        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        do {
            try proc.run()
            Diag.log(.info, .app, "Interactive process started", data: [
                "pid": proc.processIdentifier,
                "sessionId": String(sessionId.prefix(8))
            ])
        } catch {
            Diag.log(.error, .app, "Failed to start interactive process", data: [
                "error": error.localizedDescription
            ])
            cont.yield(.error("Failed to start: \(error.localizedDescription)"))
            cont.finish()
            cleanup()
            return stream
        }

        // Read stdout in a detached task — all blocking I/O stays OFF the actor.
        // Parse methods are static so they never enter the actor's executor.
        let stdoutHandle = stdout.fileHandleForReading
        let capturedSessionId = sessionId
        readTask = Task.detached {
            Self.readLoop(
                handle: stdoutHandle,
                continuation: cont,
                sessionId: capturedSessionId
            )
        }

        // Log stderr in background (for debugging)
        let stderrHandle = stderr.fileHandleForReading
        Task.detached {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    // Log each line separately for clarity
                    for stderrLine in text.components(separatedBy: .newlines) where !stderrLine.isEmpty {
                        Diag.log(.warn, .app, "stderr: \(String(stderrLine.prefix(500)))")
                    }
                }
            }
        }

        return stream
    }

    // MARK: - Disconnect

    func disconnect() {
        guard let proc = process, proc.isRunning else {
            cleanup()
            return
        }
        Diag.log(.info, .app, "Disconnecting interactive session", data: [
            "pid": proc.processIdentifier
        ])
        proc.terminate()
        // Give it 2 seconds to exit gracefully
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak proc] in
            if proc?.isRunning == true {
                proc?.interrupt() // SIGINT
            }
        }
        cleanup()
    }

    // MARK: - Send Messages

    /// Send a user message to the Claude process.
    func sendUserMessage(_ text: String, sessionId: String) {
        let msg: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": text
            ],
            "session_id": sessionId,
            "parent_tool_use_id": NSNull()
        ]
        writeJSON(msg)
        Diag.log(.info, .app, "Sent user message", data: [
            "length": text.count,
            "sessionId": String(sessionId.prefix(8))
        ])
    }

    /// Send a control response to approve a tool use.
    ///
    /// The CLI's processLine() matches responses via `q.response.request_id`,
    /// so request_id MUST be inside the `response` object (not at top level).
    func sendApproval(requestId: String, toolName: String, input: [String: Any]) {
        let msg: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": [
                    "behavior": "allow",
                    "updatedInput": input
                ]
            ]
        ]
        writeJSON(msg)
        Diag.log(.info, .app, "Sent approval", data: [
            "requestId": requestId,
            "tool": toolName
        ])
    }

    /// Send a control response to reject a tool use.
    ///
    /// The CLI's processLine() matches responses via `q.response.request_id`,
    /// so request_id MUST be inside the `response` object (not at top level).
    func sendRejection(requestId: String, message: String) {
        let msg: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": [
                    "behavior": "deny",
                    "message": message
                ]
            ]
        ]
        writeJSON(msg)
        Diag.log(.info, .app, "Sent rejection", data: [
            "requestId": requestId
        ])
    }

    // MARK: - Diagnostic Info

    var diagnosticInfo: (connected: Bool, sessionId: String?, pid: Int32?) {
        (
            connected: isConnected,
            sessionId: connectedSessionId,
            pid: process?.processIdentifier
        )
    }

    // MARK: - Static: Read Loop (runs off-actor in Task.detached)

    /// Blocking read loop that runs entirely off the actor.
    /// Uses static parse methods to avoid entering the actor's executor.
    private static func readLoop(
        handle: FileHandle,
        continuation: AsyncStream<Event>.Continuation,
        sessionId: String
    ) {
        var buffer = ""

        while true {
            let data = handle.availableData
            if data.isEmpty { break } // EOF

            guard let chunk = String(data: data, encoding: .utf8) else { continue }
            buffer += chunk

            // Process complete lines
            while let newlineRange = buffer.range(of: "\n") {
                let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = String(buffer[newlineRange.upperBound...])

                if !line.isEmpty {
                    if let event = parseLine(line, sessionId: sessionId) {
                        continuation.yield(event)
                    }
                }
            }
        }

        continuation.yield(.disconnected)
        continuation.finish()
    }

    // MARK: - Static: Parse NDJSON Line

    private static func parseLine(_ line: String, sessionId: String) -> Event? {
        // Log all raw stdout lines for protocol debugging
        let preview = String(line.prefix(300))
        Diag.log(.info, .app, "stdout<<< \(preview)")

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            Diag.log(.warn, .app, "Unparseable stdout line: \(preview)")
            return nil
        }

        switch type {
        case "system":
            return parseSystemEvent(json, sessionId: sessionId)
        case "stream_event":
            return parseStreamEvent(json)
        case "assistant":
            return parseAssistantMessage(json)
        case "control_request":
            return parseControlRequest(json)
        case "result":
            return parseResult(json)
        default:
            Diag.log(.warn, .app, "Unrecognized event type: \(type)", data: [
                "preview": String(line.prefix(500))
            ])
            return nil
        }
    }

    private static func parseSystemEvent(_ json: [String: Any], sessionId: String) -> Event? {
        let subtype = json["subtype"] as? String
        guard subtype == "init" else { return nil }

        let sid = json["session_id"] as? String ?? sessionId
        let model = json["model"] as? String
        let permMode = json["permissionMode"] as? String

        Diag.log(.info, .app, "Interactive session init", data: [
            "sessionId": String(sid.prefix(8)),
            "model": model ?? "unknown",
            "permissionMode": permMode ?? "default"
        ])

        return .connected(sessionId: sid, model: model, permissionMode: permMode)
    }

    private static func parseStreamEvent(_ json: [String: Any]) -> Event? {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String else {
            return nil
        }

        switch eventType {
        case "content_block_start":
            if let block = event["content_block"] as? [String: Any],
               let blockType = block["type"] as? String,
               blockType == "tool_use",
               let id = block["id"] as? String,
               let name = block["name"] as? String {
                return .toolUseStart(id: id, name: name)
            }
            return nil

        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return nil }

            switch deltaType {
            case "text_delta":
                if let text = delta["text"] as? String {
                    return .streamText(text)
                }
            case "thinking_delta":
                if let thinking = delta["thinking"] as? String {
                    return .streamThinking(thinking)
                }
            default:
                break
            }
            return nil

        case "message_stop":
            return .messageComplete(nil)

        default:
            return nil
        }
    }

    private static func parseAssistantMessage(_ json: [String: Any]) -> Event? {
        // Parse into a ParsedMessage using the existing parser infrastructure
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let line = String(data: data, encoding: .utf8),
              let parsed = JSONLParser.parseLine(line) else {
            return .messageComplete(nil)
        }
        return .messageComplete(parsed)
    }

    private static func parseControlRequest(_ json: [String: Any]) -> Event? {
        guard let requestId = json["request_id"] as? String,
              let request = json["request"] as? [String: Any],
              let toolName = request["tool_name"] as? String else {
            return nil
        }

        let input = request["input"] as? [String: Any] ?? [:]
        let inputJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            inputJSON = str
        } else {
            inputJSON = "{}"
        }

        Diag.log(.info, .app, "Permission request", data: [
            "requestId": requestId,
            "tool": toolName
        ])

        return .permissionRequest(requestId: requestId, toolName: toolName, inputJSON: inputJSON)
    }

    private static func parseResult(_ json: [String: Any]) -> Event? {
        let durationMs = json["duration_ms"] as? Int ?? 0
        let cost = json["total_cost_usd"] as? Double
        return .result(durationMs: durationMs, costUSD: cost)
    }

    // MARK: - Private: Write JSON to stdin

    private func writeJSON(_ object: [String: Any]) {
        guard let pipe = stdinPipe else {
            Diag.log(.warn, .app, "Cannot write: stdin pipe is nil")
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              var line = String(data: data, encoding: .utf8) else {
            Diag.log(.error, .app, "Failed to serialize JSON for stdin")
            return
        }

        // Debug: log the exact JSON being sent (truncated for readability)
        Diag.log(.info, .app, "stdin>>> \(String(line.prefix(1000)))")

        // Re-serialize as compact single line for the pipe
        if let compactData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let compactLine = String(data: compactData, encoding: .utf8) {
            line = compactLine
        }

        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        pipe.fileHandleForWriting.write(lineData)
    }

    // MARK: - Private: Lifecycle

    private func handleTermination() {
        let exitCode = process?.terminationStatus ?? -1
        Diag.log(.info, .app, "Interactive process terminated", data: [
            "exitCode": exitCode
        ])
        continuation?.yield(.disconnected)
        continuation?.finish()
        cleanup()
    }

    private func cleanup() {
        readTask?.cancel()
        readTask = nil
        process = nil
        stdinPipe = nil
        continuation = nil
        connectedSessionId = nil
    }

    // MARK: - Claude Binary Discovery

    /// Find the claude binary, checking common installation paths.
    static func findClaudeBinary() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Check NVM versions
        let nvmBase = "\(NSHomeDirectory())/.nvm/versions/node"
        if let nodes = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for node in nodes.sorted().reversed() {
                let path = "\(nvmBase)/\(node)/bin/claude"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        // Check VS Code extension native binary
        let vscodeExtBase = "\(NSHomeDirectory())/.vscode/extensions"
        if let exts = try? FileManager.default.contentsOfDirectory(atPath: vscodeExtBase) {
            for ext in exts.sorted().reversed() where ext.hasPrefix("anthropic.claude-code-") {
                let path = "\(vscodeExtBase)/\(ext)/resources/native-binary/claude"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        return nil
    }
}
