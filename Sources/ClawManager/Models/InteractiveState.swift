import Foundation

// MARK: - Connection State

enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    case terminated(String)

    var isActive: Bool {
        if case .connected = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .disconnected:      "Disconnected"
        case .connecting:        "Connecting..."
        case .connected:         "Connected"
        case .error(let msg):    msg
        case .terminated(let r): r
        }
    }
}

// MARK: - Live Message (streaming token-by-token)

struct LiveMessage: Identifiable, Sendable {
    let id: String
    var role: ParsedMessage.MessageRole
    var textAccumulator: String
    var thinkingAccumulator: String
    var toolCalls: [LiveToolCall]
    var isComplete: Bool
    var timestamp: Date
}

// MARK: - Live Tool Call

struct LiveToolCall: Identifiable, Sendable, Equatable {
    static func == (lhs: LiveToolCall, rhs: LiveToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isComplete == rhs.isComplete
    }

    let id: String
    let name: String
    var inputJson: String
    var isComplete: Bool
    var result: String?
    var isError: Bool
}

// MARK: - Interactive Session Events

enum InteractiveEvent: Sendable {
    case connectionChanged(ConnectionState)
    case messageUpdated(LiveMessage)
    case messageCompleted(LiveMessage)
    case toolCallStarted(LiveToolCall)
    case resultReceived(isError: Bool, result: String?, costUsd: Double?)
    case processExited  // CLI process ended normally; connection stays alive for next message
    case error(String)
}
