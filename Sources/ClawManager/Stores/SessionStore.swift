import Foundation
import Observation
import Combine

@Observable
@MainActor
final class SessionStore {
    // MARK: - Published State
    var sessions: [SessionSummary] = []
    var projects: [Project] = []
    var isLoading = true
    var selectedDetail: SessionDetail?

    // MARK: - Interactive State
    var connectionState: ConnectionState = .disconnected
    var isStreaming = false
    var currentStreamingText = ""
    var currentStreamingThinking = ""
    var pendingControlRequest: ControlRequest?

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(sessionId: String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var sessionId: String? {
            if case .connected(let id) = self { return id }
            return nil
        }
    }

    struct ControlRequest: Equatable {
        let requestId: String
        let toolName: String
        let inputJSON: String

        static func == (lhs: ControlRequest, rhs: ControlRequest) -> Bool {
            lhs.requestId == rhs.requestId
        }
    }

    // MARK: - Private
    private let discovery = SessionDiscoveryService()
    private let fileWatcher = FileWatcherService()
    private var watcherSubscription: AnyCancellable?
    private var pollingTask: Task<Void, Never>?
    private let tailService = SessionTailService()
    private var tailTask: Task<Void, Never>?
    private var stateDumpTask: Task<Void, Never>?
    private let startTime = Date()

    private let interactiveService = InteractiveSessionService()
    private var interactiveEventTask: Task<Void, Never>?

    init() {}

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        Diag.log(.info, .app, "startMonitoring")

        // Initial load
        Task {
            await refresh()
        }

        // File system watching (debounced at 500ms)
        fileWatcher.startWatching()
        watcherSubscription = fileWatcher.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refresh()
                }
            }

        // Periodic process polling (every 5s) for status changes
        // that don't trigger file modifications
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refresh()
            }
        }

        // Periodic state snapshot (every 3s) for diagnostic probing
        stateDumpTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await dumpState()
            }
        }
    }

    func stopMonitoring() {
        Diag.log(.info, .app, "stopMonitoring")
        pollingTask?.cancel()
        stateDumpTask?.cancel()
        watcherSubscription?.cancel()
        fileWatcher.stopWatching()
        stopTailing()
        disconnectInteractive()
    }

    // MARK: - Refresh

    func refresh() async {
        let t0 = Diag.now()
        let newSessions = await discovery.discoverAll()
        Diag.elapsed(t0, .discovery, "discoverAll")

        // Build projects from the sessions we already have (avoid double scan)
        var projectMap: [String: Project] = [:]
        for s in newSessions {
            var project = projectMap[s.workspacePath] ?? Project(
                name: s.projectName,
                workspacePath: s.workspacePath,
                mangledPath: s.workspacePath.replacingOccurrences(of: "/", with: "-"),
                sessionCount: 0,
                activeSessionCount: 0
            )
            project.sessionCount += 1
            if s.status == .active || s.status == .waiting {
                project.activeSessionCount += 1
            }
            projectMap[s.workspacePath] = project
        }
        let newProjects = projectMap.values.sorted {
            if $0.activeSessionCount != $1.activeSessionCount {
                return $0.activeSessionCount > $1.activeSessionCount
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        // Only update if data actually changed to prevent unnecessary SwiftUI redraws
        let sessionsChanged = sessions != newSessions
        if sessionsChanged {
            sessions = newSessions
            Diag.log(.info, .discovery, "Sessions updated", data: [
                "total": newSessions.count,
                "active": newSessions.filter { $0.status == .active }.count,
                "waiting": newSessions.filter { $0.status == .waiting }.count
            ])
        }
        if projects != newProjects {
            projects = newProjects
        }
        if isLoading { isLoading = false }

        // If we have a selected detail, refresh its summary when it changed.
        // Skip full message reload if we're tailing or connected interactively —
        // both handle new messages incrementally.
        if let detail = selectedDetail {
            let isLive = tailTask != nil || connectionState.isConnected
            if let updated = newSessions.first(where: { $0.sessionId == detail.summary.sessionId }),
               updated != detail.summary {
                if isLive {
                    // Only update the summary metadata, keep messages intact
                    selectedDetail?.summary = updated
                } else {
                    let url = URL(fileURLWithPath: updated.jsonlPath)
                    let messages = (try? JSONLParser.readAll(at: url)) ?? []
                    let subagents = SubagentLoader.loadSubagents(sessionId: updated.sessionId, jsonlPath: updated.jsonlPath)
                    selectedDetail = SessionDetail(summary: updated, messages: messages, subagents: subagents)
                }
            }
        }
    }

    // MARK: - Detail Loading

    func loadDetail(for sessionId: String) async {
        // Disconnect any active interactive session first
        disconnectInteractive()

        guard let summary = sessions.first(where: { $0.sessionId == sessionId }) else {
            selectedDetail = nil
            stopTailing()
            return
        }

        Diag.log(.info, .detail, "Loading detail", data: [
            "sessionId": String(sessionId.prefix(8)),
            "project": summary.projectName,
            "status": "\(summary.status)"
        ])

        let url = URL(fileURLWithPath: summary.jsonlPath)
        let t1 = Diag.now()
        let messages = (try? JSONLParser.readAll(at: url)) ?? []
        Diag.elapsed(t1, .detail, "readAll")
        let subagents = SubagentLoader.loadSubagents(sessionId: summary.sessionId, jsonlPath: summary.jsonlPath)
        selectedDetail = SessionDetail(summary: summary, messages: messages, subagents: subagents)

        Diag.log(.info, .detail, "Detail loaded", data: [
            "messageCount": messages.count,
            "subagentCount": subagents.count
        ])

        // Start tailing from the current file size so we only get NEW lines
        let fileSize = Self.fileSize(at: summary.jsonlPath)
        startTailing(path: summary.jsonlPath, fromOffset: fileSize)
    }

    func clearDetail() {
        Diag.log(.info, .detail, "Cleared detail")
        disconnectInteractive()
        selectedDetail = nil
        stopTailing()
    }

    // MARK: - Interactive Session

    /// Connect to a session interactively. Stops tailing and spawns a Claude process.
    func connectInteractive(sessionId: String) async {
        guard let summary = sessions.first(where: { $0.sessionId == sessionId }) else { return }

        connectionState = .connecting
        pendingControlRequest = nil
        isStreaming = false
        currentStreamingText = ""
        currentStreamingThinking = ""

        // Stop tailing — the interactive service will provide live events
        stopTailing()

        Diag.log(.info, .app, "Connecting interactively", data: [
            "sessionId": String(sessionId.prefix(8))
        ])

        let stream = await interactiveService.connect(
            sessionId: sessionId,
            workDir: summary.workspacePath,
            permissionMode: summary.permissionMode?.rawValue
        )

        // Transition to connected immediately — the CLI's init event
        // only arrives when the first message is sent, so we can't wait.
        // The process is running and ready for input at this point.
        connectionState = .connected(sessionId: sessionId)
        Diag.log(.info, .app, "Interactive connected (process ready)", data: [
            "sessionId": String(sessionId.prefix(8))
        ])

        interactiveEventTask = Task {
            for await event in stream {
                guard !Task.isCancelled else { break }
                await handleInteractiveEvent(event)
            }
        }
    }

    /// Disconnect the interactive session. Resumes tailing.
    func disconnectInteractive() {
        guard connectionState != .disconnected else { return }

        interactiveEventTask?.cancel()
        interactiveEventTask = nil
        Task { await interactiveService.disconnect() }

        connectionState = .disconnected
        isStreaming = false
        currentStreamingText = ""
        currentStreamingThinking = ""
        pendingControlRequest = nil

        // Resume tailing so the read-only view stays live
        if let detail = selectedDetail {
            let fileSize = Self.fileSize(at: detail.summary.jsonlPath)
            startTailing(path: detail.summary.jsonlPath, fromOffset: fileSize)
        }

        Diag.log(.info, .app, "Disconnected interactive session")
    }

    /// Take over a session from VS Code by killing its process first.
    func takeOverSession(sessionId: String) async {
        guard let summary = sessions.first(where: { $0.sessionId == sessionId }),
              let pid = summary.pid else { return }

        Diag.log(.info, .app, "Taking over session", data: [
            "sessionId": String(sessionId.prefix(8)),
            "killingPid": pid
        ])

        // SIGTERM the existing process
        kill(pid, SIGTERM)

        // Wait for the process to exit
        try? await Task.sleep(for: .milliseconds(1500))

        // Now connect
        await connectInteractive(sessionId: sessionId)
    }

    /// Send a user message through the interactive service.
    func sendMessage(_ text: String) async {
        guard case .connected(let sessionId) = connectionState else { return }

        // Add the user's message to the feed immediately so it's visible
        let userMessage = ParsedMessage(
            id: UUID().uuidString,
            type: .user,
            timestamp: Date(),
            role: .user,
            content: [.text(text)],
            model: nil,
            slug: nil,
            gitBranch: nil,
            version: nil,
            sessionId: sessionId,
            cwd: nil,
            permissionMode: nil
        )
        selectedDetail?.messages.append(userMessage)

        isStreaming = true
        currentStreamingText = ""
        currentStreamingThinking = ""
        await interactiveService.sendUserMessage(text, sessionId: sessionId)
    }

    /// Approve a pending tool use.
    func approveToolUse() async {
        guard let request = pendingControlRequest else { return }

        // Parse input back from JSON for the updatedInput field
        let input: [String: Any]
        if let data = request.inputJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            input = parsed
        } else {
            input = [:]
        }

        await interactiveService.sendApproval(
            requestId: request.requestId,
            toolName: request.toolName,
            input: input
        )
        pendingControlRequest = nil
        // Show "Thinking..." while Claude processes the approved tool
        isStreaming = true
        currentStreamingText = ""
        currentStreamingThinking = ""
    }

    /// Answer an AskUserQuestion control request.
    /// `answers` maps question text to the selected option label (or custom "Other" text).
    func answerQuestion(answers: [String: String]) async {
        guard let request = pendingControlRequest else { return }

        Diag.log(.info, .app, "answerQuestion called", data: [
            "requestId": request.requestId,
            "toolName": request.toolName,
            "answerCount": answers.count
        ])

        // Log each answer for debugging
        for (question, answer) in answers {
            Diag.log(.info, .app, "  Q: \(String(question.prefix(80))) → A: \(String(answer.prefix(80)))")
        }

        // Reconstruct the original input and add the answers dict
        var input: [String: Any]
        if let data = request.inputJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            input = parsed
        } else {
            Diag.log(.error, .app, "Failed to parse inputJSON back to dict")
            input = [:]
        }
        input["answers"] = answers

        // Log the full updatedInput for debugging
        if let debugData = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
           let debugStr = String(data: debugData, encoding: .utf8) {
            Diag.log(.info, .app, "updatedInput: \(String(debugStr.prefix(2000)))")
        }

        await interactiveService.sendApproval(
            requestId: request.requestId,
            toolName: request.toolName,
            input: input
        )
        pendingControlRequest = nil
        // Show "Thinking..." while Claude processes the answer
        isStreaming = true
        currentStreamingText = ""
        currentStreamingThinking = ""
    }

    /// Reject a pending tool use.
    func rejectToolUse(message: String = "User rejected this action") async {
        guard let request = pendingControlRequest else { return }
        await interactiveService.sendRejection(
            requestId: request.requestId,
            message: message
        )
        pendingControlRequest = nil
        // Show "Thinking..." while Claude processes the rejection
        isStreaming = true
        currentStreamingText = ""
        currentStreamingThinking = ""
    }

    // MARK: - Interactive Event Handling

    private func handleInteractiveEvent(_ event: InteractiveSessionService.Event) async {
        switch event {
        case .connected(let sessionId, _, _):
            connectionState = .connected(sessionId: sessionId)
            Diag.log(.info, .app, "Interactive connected", data: [
                "sessionId": String(sessionId.prefix(8))
            ])

        case .streamText(let text):
            isStreaming = true
            currentStreamingText += text

        case .streamThinking(let text):
            isStreaming = true
            currentStreamingThinking += text

        case .toolUseStart(let id, let name):
            Diag.log(.info, .app, "Tool use started", data: [
                "id": String(id.prefix(12)),
                "name": name
            ])

        case .permissionRequest(let requestId, let toolName, let inputJSON):
            // Claude stopped streaming — it's waiting for user input
            isStreaming = false
            currentStreamingText = ""
        currentStreamingThinking = ""
            pendingControlRequest = ControlRequest(
                requestId: requestId,
                toolName: toolName,
                inputJSON: inputJSON
            )

        case .messageComplete(let parsed):
            isStreaming = false
            currentStreamingText = ""
        currentStreamingThinking = ""
            if let msg = parsed {
                selectedDetail?.messages.append(msg)
            }

        case .result(let durationMs, let cost):
            isStreaming = false
            currentStreamingText = ""
        currentStreamingThinking = ""
            Diag.log(.info, .app, "Interactive result", data: [
                "durationMs": durationMs,
                "costUSD": cost ?? 0.0
            ])

        case .error(let msg):
            Diag.log(.error, .app, "Interactive error: \(msg)")
            isStreaming = false

        case .disconnected:
            if connectionState.isConnected {
                // Unexpected disconnection — process died
                Diag.log(.warn, .app, "Interactive session disconnected unexpectedly")
                disconnectInteractive()
            }
        }
    }

    // MARK: - JSONL File Tailing

    private func startTailing(path: String, fromOffset: UInt64) {
        stopTailing()

        tailTask = Task {
            let stream = await tailService.startTailing(path: path, fromOffset: fromOffset)
            for await message in stream {
                guard !Task.isCancelled else { break }
                // Append new messages to the detail view in real time
                selectedDetail?.messages.append(message)
            }
        }
    }

    private func stopTailing() {
        tailTask?.cancel()
        tailTask = nil
        Task { await tailService.stopTailing() }
    }

    // MARK: - State Snapshot (for diagnostic probing)

    func dumpState() async {
        let tailInfo = await tailService.diagnosticInfo
        let interactiveInfo = await interactiveService.diagnosticInfo

        let sessionStats = StateSnapshot.SessionStats(
            total: sessions.count,
            active: sessions.filter { $0.status == .active }.count,
            waiting: sessions.filter { $0.status == .waiting }.count,
            idle: sessions.filter { $0.status == .idle }.count,
            stale: sessions.filter { $0.status == .stale }.count
        )

        let selected: StateSnapshot.SelectedSessionInfo?
        if let detail = selectedDetail {
            selected = StateSnapshot.SelectedSessionInfo(
                sessionId: String(detail.summary.sessionId.prefix(8)),
                project: detail.summary.projectName,
                status: "\(detail.summary.status)",
                messageCount: detail.messages.count,
                hasPendingInteraction: detail.summary.pendingInteraction != nil,
                pendingToolName: detail.summary.pendingInteraction?.toolName,
                pendingType: detail.summary.pendingInteraction?.type.rawValue,
                permissionMode: detail.summary.permissionMode?.rawValue
            )
        } else {
            selected = nil
        }

        let tail: StateSnapshot.TailInfo = StateSnapshot.TailInfo(
            active: tailInfo.active,
            path: tailInfo.path.map { ($0 as NSString).lastPathComponent },
            offsetBytes: tailInfo.offset,
            messagesTailed: tailInfo.messagesTailed
        )

        let interactive = StateSnapshot.InteractiveInfo(
            connected: interactiveInfo.connected,
            sessionId: interactiveInfo.sessionId.map { String($0.prefix(8)) },
            pid: interactiveInfo.pid,
            streaming: isStreaming,
            pendingRequestId: pendingControlRequest?.requestId
        )

        let snapshot = StateSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sessions: sessionStats,
            projects: projects.count,
            selectedSession: selected,
            tail: tail,
            interactive: interactive
        )

        Diag.writeState(snapshot)
    }

    // MARK: - Helpers

    private static func fileSize(at path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return size
    }
}
