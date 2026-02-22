import Foundation

struct SubagentSummary: Identifiable, Sendable {
    var id: String { agentId }

    let agentId: String
    let jsonlPath: String
    let taskDescription: String
    let messageCount: Int
    let lastActivity: Date
    let isCompleted: Bool
}

// MARK: - Loader

@MainActor
enum SubagentLoader {

    private static var cache: [String: CachedSubagent] = [:]

    private struct CachedSubagent {
        let mtime: Date
        let summary: SubagentSummary
    }

    /// Discover and build summaries for all subagents of a session.
    /// Uses head/tail reads and mtime caching to avoid expensive full-file parses.
    static func loadSubagents(sessionId: String, jsonlPath: String) -> [SubagentSummary] {
        let fm = FileManager.default
        let sessionDir = URL(fileURLWithPath: jsonlPath)
            .deletingLastPathComponent()
            .appendingPathComponent(sessionId)
            .appendingPathComponent("subagents")

        guard fm.fileExists(atPath: sessionDir.path),
              let files = try? fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { buildSummary(from: $0) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func buildSummary(from url: URL) -> SubagentSummary? {
        let pathKey = url.path

        // Check file modification time
        guard let mtime = JSONLParser.lastModified(at: url) else { return nil }

        // Return cached summary if file hasn't changed
        if let cached = cache[pathKey], cached.mtime == mtime {
            return cached.summary
        }

        // Extract agentId from filename: "agent-abc1234.jsonl" → "abc1234"
        let filename = url.deletingPathExtension().lastPathComponent
        let agentId = filename.hasPrefix("agent-") ? String(filename.dropFirst(6)) : filename

        // Read only the first few lines for task description
        let headMessages = (try? JSONLParser.readHead(at: url, count: 5)) ?? []
        guard !headMessages.isEmpty else { return nil }

        let taskDescription: String = {
            guard let firstUser = headMessages.first(where: { $0.role == .user }) else {
                return "Unknown task"
            }
            let text = firstUser.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined(separator: " ")
            return Formatters.truncate(text, to: 200)
        }()

        // Read only the last few lines for completion status
        let tailMessages = (try? JSONLParser.readTail(at: url, count: 5)) ?? []

        let isCompleted: Bool = {
            guard let lastAssistant = tailMessages.last(where: { $0.role == .assistant }) else {
                return false
            }
            let hasText = lastAssistant.content.contains { if case .text = $0 { return true }; return false }
            let hasToolUse = lastAssistant.content.contains { if case .toolUse = $0 { return true }; return false }
            return hasText && !hasToolUse
        }()

        // Count lines (fast byte scan, no parsing)
        let lineCount = JSONLParser.lineCount(at: url)

        let summary = SubagentSummary(
            agentId: agentId,
            jsonlPath: url.path,
            taskDescription: taskDescription,
            messageCount: lineCount,
            lastActivity: mtime,
            isCompleted: isCompleted
        )

        cache[pathKey] = CachedSubagent(mtime: mtime, summary: summary)
        return summary
    }
}
