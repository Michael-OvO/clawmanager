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

    // MARK: - Private
    private let discovery = SessionDiscoveryService()
    private let fileWatcher = FileWatcherService()
    private var watcherSubscription: AnyCancellable?
    private var pollingTask: Task<Void, Never>?
    private let tailService = SessionTailService()
    private var tailTask: Task<Void, Never>?
    private var stateDumpTask: Task<Void, Never>?
    private let startTime = Date()

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
        // Skip full message reload if we're tailing — the tail stream handles
        // new messages incrementally, and reassigning selectedDetail would
        // reset scroll position.
        if let detail = selectedDetail {
            let isTailing = tailTask != nil
            if let updated = newSessions.first(where: { $0.sessionId == detail.summary.sessionId }),
               updated != detail.summary {
                if isTailing {
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
        selectedDetail = nil
        stopTailing()
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
                pendingToolName: detail.summary.pendingInteraction?.toolName
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

        let snapshot = StateSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sessions: sessionStats,
            projects: projects.count,
            selectedSession: selected,
            tail: tail
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
