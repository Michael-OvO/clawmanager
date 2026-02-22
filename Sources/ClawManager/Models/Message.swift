import Foundation

struct ParsedMessage: Identifiable, Sendable {
    let id: String
    let type: MessageType
    let timestamp: Date?
    let role: MessageRole?
    let content: [MessageContent]
    let model: String?
    let slug: String?
    let gitBranch: String?
    let version: String?
    let sessionId: String?
    let cwd: String?

    enum MessageType: String, Sendable {
        case user
        case assistant
        case system
        case progress
        case fileHistorySnapshot = "file-history-snapshot"
        case queueOperation = "queue-operation"
        case unknown
    }

    enum MessageRole: String, Sendable {
        case user
        case assistant
    }
}

enum MessageContent: Identifiable, Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, inputJSON: String)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    var id: String {
        switch self {
        case .text(let t):                    "text-\(t.hashValue)"
        case .thinking(let t):                "thinking-\(t.hashValue)"
        case .toolUse(let id, _, _):          "tooluse-\(id)"
        case .toolResult(let id, _, _):       "toolresult-\(id)"
        }
    }

    var isToolUse: Bool {
        if case .toolUse = self { return true }
        return false
    }

    var toolUseName: String? {
        if case .toolUse(_, let name, _) = self { return name }
        return nil
    }
}
