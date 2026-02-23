import Foundation

actor SessionDiscoveryService {
    private var cache: [String: CachedSession] = [:]

    private struct CachedSession {
        let mtime: Date
        let summary: SessionSummary
    }

    private static let maxStaleDays: TimeInterval = 14 * 86400

    // MARK: - Public API

    /// Discover all sessions across all projects.
    func discoverAll() -> [SessionSummary] {
        let projectsDir = PathUtilities.projectsDir
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectsDir.path) else { return [] }

        guard let workspaceDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true })
        else { return [] }

        let cutoff = Date().addingTimeInterval(-Self.maxStaleDays)
        let processes = ProcessMonitorService.findClaudeProcesses()

        var allSessions: [SessionSummary] = []

        for dir in workspaceDirs {
            let sessions = discoverWorkspace(dir: dir, cutoff: cutoff, processes: processes)
            allSessions.append(contentsOf: sessions)
        }
        return allSessions.sorted {
            if $0.lastActivity != $1.lastActivity {
                return $0.lastActivity > $1.lastActivity
            }
            return $0.sessionId < $1.sessionId
        }
    }

    /// Discover projects (sessions grouped by workspace).
    func discoverProjects() -> [Project] {
        let sessions = discoverAll()
        var map: [String: Project] = [:]

        for s in sessions {
            var project = map[s.workspacePath] ?? Project(
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
            map[s.workspacePath] = project
        }

        return map.values.sorted {
            if $0.activeSessionCount != $1.activeSessionCount {
                return $0.activeSessionCount > $1.activeSessionCount
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Private

    private func discoverWorkspace(
        dir: URL,
        cutoff: Date,
        processes: [ClaudeProcess]
    ) -> [SessionSummary] {
        let fm = FileManager.default
        let mangledName = dir.lastPathComponent
        let workspacePath = PathUtilities.demangleWorkspacePath(mangledName)
        let projectName = PathUtilities.projectName(from: workspacePath)

        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        var sessions: [SessionSummary] = []

        for entry in entries {
            let name = entry.lastPathComponent
            var jsonlURL: URL?
            var sessionId: String?

            // <uuid>.jsonl files
            if name.hasSuffix(".jsonl") {
                let id = String(name.dropLast(6))
                if PathUtilities.isUUID(id) {
                    sessionId = id
                    jsonlURL = entry
                }
            }

            // <uuid>/ directories containing <uuid>.jsonl
            let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues?.isDirectory == true && PathUtilities.isUUID(name) {
                let nested = entry.appendingPathComponent("\(name).jsonl")
                if fm.fileExists(atPath: nested.path) {
                    sessionId = name
                    jsonlURL = nested
                }
            }

            guard let sid = sessionId, let jpath = jsonlURL else { continue }

            guard let mtime = JSONLParser.lastModified(at: jpath),
                  mtime > cutoff else { continue }

            let pathKey = jpath.path

            // Use cache if mtime unchanged
            if let cached = cache[pathKey], cached.mtime == mtime {
                var summary = cached.summary
                let proc = processes.first { $0.sessionId == sid }
                summary.pid = proc?.pid
                summary.status = Self.computeStatus(pid: summary.pid, pending: summary.pendingInteraction, mtime: mtime)
                sessions.append(summary)
                continue
            }

            // Build fresh summary
            let summary = buildSummary(
                sessionId: sid,
                jsonlPath: jpath,
                workspacePath: workspacePath,
                projectName: projectName,
                processes: processes
            )

            cache[pathKey] = CachedSession(mtime: mtime, summary: summary)
            sessions.append(summary)
        }

        return sessions
    }

    private func buildSummary(
        sessionId: String,
        jsonlPath: URL,
        workspacePath: String,
        projectName: String,
        processes: [ClaudeProcess]
    ) -> SessionSummary {
        let tail = (try? JSONLParser.readTail(at: jsonlPath, count: 40)) ?? []
        let mtime = JSONLParser.lastModified(at: jsonlPath) ?? Date.distantPast

        let previews = JSONLParser.extractPreviews(from: tail, count: 4)
        let pending = JSONLParser.detectPendingInteraction(in: tail)
        let (slug, gitBranch, cliVersion, model) = JSONLParser.extractMetadata(from: tail)
        let permMode = JSONLParser.extractPermissionMode(from: tail)

        let proc = processes.first { $0.sessionId == sessionId }
        let pid = proc?.pid
        let status = Self.computeStatus(pid: pid, pending: pending, mtime: mtime)

        // Count subagents
        let subagentDir = jsonlPath.deletingLastPathComponent()
            .appendingPathComponent(sessionId)
            .appendingPathComponent("subagents")
        let subagentCount = (try? FileManager.default.contentsOfDirectory(atPath: subagentDir.path).count) ?? 0

        return SessionSummary(
            sessionId: sessionId,
            workspacePath: workspacePath,
            projectName: projectName,
            jsonlPath: jsonlPath.path,
            status: status,
            lastActivity: mtime,
            pid: pid,
            model: model,
            slug: slug,
            gitBranch: gitBranch,
            cliVersion: cliVersion,
            messageCount: tail.count,
            subagentCount: subagentCount,
            lastMessages: previews,
            pendingInteraction: pending,
            permissionMode: permMode
        )
    }

    private static func computeStatus(pid: Int32?, pending: PendingInteraction?, mtime: Date) -> SessionStatus {
        guard let pid = pid else { return .stale }

        guard ProcessMonitorService.isProcessAlive(pid: pid) else { return .stale }

        if pending != nil { return .waiting }

        return mtime.timeIntervalSinceNow > -30 ? .active : .idle
    }
}
