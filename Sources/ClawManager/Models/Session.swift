import Foundation

struct SessionSummary: Identifiable, Sendable, Equatable {
    static func == (lhs: SessionSummary, rhs: SessionSummary) -> Bool {
        lhs.sessionId == rhs.sessionId &&
        lhs.status == rhs.status &&
        lhs.lastActivity == rhs.lastActivity &&
        lhs.pid == rhs.pid &&
        lhs.pendingInteraction == rhs.pendingInteraction &&
        lhs.messageCount == rhs.messageCount &&
        lhs.subagentCount == rhs.subagentCount
    }

    var id: String { sessionId }

    let sessionId: String
    let workspacePath: String
    let projectName: String
    let jsonlPath: String
    var status: SessionStatus
    let lastActivity: Date
    var pid: Int32?
    let model: String?
    let slug: String?
    let gitBranch: String?
    let cliVersion: String?
    let messageCount: Int
    let subagentCount: Int
    let lastMessages: [MessagePreview]
    var pendingInteraction: PendingInteraction?
}

struct SessionDetail: Sendable {
    let summary: SessionSummary
    let messages: [ParsedMessage]
    let subagents: [SubagentSummary]
}

struct MessagePreview: Sendable {
    let role: String
    let text: String
    let toolName: String?
    let timestamp: Date?
}
