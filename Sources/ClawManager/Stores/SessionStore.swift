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

    // MARK: - Interactive Session State
    var interactiveSessionId: String?
    var connectionState: ConnectionState = .disconnected
    var liveMessages: [LiveMessage] = []
    var currentStreamingMessage: LiveMessage?
    var pendingToolApproval: LiveToolCall?

    // MARK: - Private
    private let discovery = SessionDiscoveryService()
    private let fileWatcher = FileWatcherService()
    private var watcherSubscription: AnyCancellable?
    private var pollingTask: Task<Void, Never>?
    private let interactiveService = InteractiveSessionService()
    private var interactiveEventTask: Task<Void, Never>?

    init() {}

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
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
    }

    func stopMonitoring() {
        pollingTask?.cancel()
        watcherSubscription?.cancel()
        fileWatcher.stopWatching()
        disconnectFromSession()
    }

    // MARK: - Refresh

    func refresh() async {
        let newSessions = await discovery.discoverAll()

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
        if sessions != newSessions {
            sessions = newSessions
        }
        if projects != newProjects {
            projects = newProjects
        }
        if isLoading { isLoading = false }

        // If we have a selected detail, refresh it only when the summary actually changed.
        // Skip entirely during an active interactive session — the live event stream
        // provides real-time updates, and reassigning selectedDetail would destroy
        // the InputBarView's focus state.
        if let detail = selectedDetail {
            let isInteractiveTarget = interactiveSessionId == detail.summary.sessionId
                && connectionState == .connected
            if !isInteractiveTarget,
               let updated = newSessions.first(where: { $0.sessionId == detail.summary.sessionId }),
               updated != detail.summary {
                let url = URL(fileURLWithPath: updated.jsonlPath)
                let messages = (try? JSONLParser.readAll(at: url)) ?? []
                let subagents = SubagentLoader.loadSubagents(sessionId: updated.sessionId, jsonlPath: updated.jsonlPath)
                selectedDetail = SessionDetail(summary: updated, messages: messages, subagents: subagents)
            }
        }
    }

    // MARK: - Detail Loading

    func loadDetail(for sessionId: String) async {
        guard let summary = sessions.first(where: { $0.sessionId == sessionId }) else {
            selectedDetail = nil
            return
        }

        let url = URL(fileURLWithPath: summary.jsonlPath)
        let messages = (try? JSONLParser.readAll(at: url)) ?? []
        let subagents = SubagentLoader.loadSubagents(sessionId: summary.sessionId, jsonlPath: summary.jsonlPath)
        selectedDetail = SessionDetail(summary: summary, messages: messages, subagents: subagents)
    }

    func clearDetail() {
        selectedDetail = nil
    }

    // MARK: - Interactive Session

    /// Connect to a session. This immediately sets the UI to "connected" state
    /// and opens a persistent event stream. The actual CLI process is spawned
    /// lazily when the user sends their first message (or immediately if the
    /// session has pending work like a tool approval).
    func connectToSession(_ sessionId: String) {
        // Don't reconnect to the same session if already connected
        guard !(connectionState == .connected && interactiveSessionId == sessionId) else { return }
        guard let summary = sessions.first(where: { $0.sessionId == sessionId }) else { return }

        // Tear down any previous interactive session
        interactiveEventTask?.cancel()
        interactiveEventTask = nil

        interactiveSessionId = sessionId
        connectionState = .connected
        liveMessages = []
        currentStreamingMessage = nil
        pendingToolApproval = nil

        // Open a persistent event stream from the service
        interactiveEventTask = Task {
            let stream = await interactiveService.openStream(
                sessionId: sessionId,
                workspacePath: summary.workspacePath
            )
            for await event in stream {
                handleInteractiveEvent(event)
            }
            // Stream ended (disconnect was called)
        }

        // If the session has pending work (tool approval, question), spawn
        // the CLI process immediately so the pending event arrives.
        if summary.pendingInteraction != nil {
            Task {
                await interactiveService.ensureProcess()
            }
        }
    }

    func disconnectFromSession() {
        interactiveEventTask?.cancel()
        interactiveEventTask = nil

        let service = interactiveService
        Task { await service.disconnect() }

        interactiveSessionId = nil
        connectionState = .disconnected
        liveMessages = []
        currentStreamingMessage = nil
        pendingToolApproval = nil
    }

    func sendInteractiveMessage(_ text: String) {
        guard connectionState == .connected else { return }

        // Add user message to live messages
        let userMsg = LiveMessage(
            id: UUID().uuidString,
            role: .user,
            textAccumulator: text,
            thinkingAccumulator: "",
            toolCalls: [],
            isComplete: true,
            timestamp: Date()
        )
        liveMessages.append(userMsg)

        // Send via service — it will spawn a process if needed
        Task {
            await interactiveService.sendMessage(text)
        }
    }

    func approveToolCall() {
        pendingToolApproval = nil
        Task {
            await interactiveService.approveToolCall()
        }
    }

    func rejectToolCall() {
        pendingToolApproval = nil
        Task {
            await interactiveService.rejectToolCall()
        }
    }

    // MARK: - Connect-and-Approve (for read-only sessions)

    /// Queued action to execute when the CLI re-emits the pending tool call after connecting.
    private var pendingAutoAction: AutoAction?

    private enum AutoAction {
        case approve
        case reject
    }

    /// Connect to a session and auto-approve its pending tool call.
    func connectAndApprove(_ sessionId: String) {
        pendingAutoAction = .approve
        connectToSession(sessionId)
    }

    /// Connect to a session and auto-reject its pending tool call.
    func connectAndReject(_ sessionId: String) {
        pendingAutoAction = .reject
        connectToSession(sessionId)
    }

    // MARK: - Interactive Event Handling

    private func handleInteractiveEvent(_ event: InteractiveEvent) {
        switch event {
        case .connectionChanged(let state):
            // Only apply connection changes if they're errors.
            // Normal connection state is managed by connectToSession/disconnectFromSession.
            if case .error = state {
                connectionState = state
            }

        case .messageUpdated(let msg):
            currentStreamingMessage = msg

        case .messageCompleted(let msg):
            currentStreamingMessage = nil
            liveMessages.append(msg)

        case .toolCallStarted(let toolCall):
            // If we have a queued auto-action (from connectAndApprove/Reject),
            // execute it immediately instead of showing the approval bar.
            if let action = pendingAutoAction {
                pendingAutoAction = nil
                switch action {
                case .approve: approveToolCall()
                case .reject:  rejectToolCall()
                }
            } else {
                pendingToolApproval = toolCall
            }

        case .resultReceived:
            pendingToolApproval = nil
            // Refresh to pick up any file changes made during the turn
            Task { await refresh() }

        case .processExited:
            // CLI process ended normally after completing a turn.
            // Keep connectionState as .connected — the user can send another message.
            currentStreamingMessage = nil
            Task { await refresh() }

        case .error(let message):
            connectionState = .error(message)
        }
    }
}
