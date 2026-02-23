import Foundation

// MARK: - Permission Mode

/// The permission mode of a Claude Code session, controlling which tools
/// require explicit user approval before execution.
enum PermissionMode: String, Sendable, Equatable {
    case `default` = "default"
    case acceptEdits = "acceptEdits"
    case plan = "plan"
    case bypassPermissions = "bypassPermissions"
    case dontAsk = "dontAsk"

    var displayName: String {
        switch self {
        case .default: "Default"
        case .acceptEdits: "Accept Edits"
        case .plan: "Plan Mode"
        case .bypassPermissions: "Yolo"
        case .dontAsk: "Don't Ask"
        }
    }

    var icon: String {
        switch self {
        case .default: "lock.shield"
        case .acceptEdits: "pencil.circle"
        case .plan: "map"
        case .bypassPermissions: "exclamationmark.shield"
        case .dontAsk: "bolt.shield"
        }
    }
}

// MARK: - Pending Interaction

/// Represents a pending interaction in a Claude Code session — a tool
/// approval, user question, or plan review that the session is blocked on.
struct PendingInteraction: Sendable, Equatable {
    enum InteractionType: String, Sendable, Equatable {
        case toolApproval   // Tool needs user permission
        case question       // AskUserQuestion
        case planReview     // ExitPlanMode plan needs approval
    }

    let type: InteractionType
    let toolUseId: String
    let toolName: String
    let toolInputJSON: String

    // Parsed tool input fields (for display)
    let toolInput: ToolInput?

    // For AskUserQuestion
    let questions: [Question]?

    // For ExitPlanMode
    let planMarkdown: String?
}

// MARK: - Tool Input (Parsed)

/// Key fields extracted from a tool_use input JSON for display purposes.
struct ToolInput: Sendable, Equatable {
    let command: String?        // Bash
    let description: String?    // Bash
    let filePath: String?       // Read, Write, Edit, Glob
    let oldString: String?      // Edit
    let newString: String?      // Edit
    let content: String?        // Write
    let pattern: String?        // Grep, Glob
    let query: String?          // WebSearch
    let url: String?            // WebFetch

    /// Best single-line summary for the tool input.
    var summary: String? {
        if let command { return command }
        if let filePath { return filePath }
        if let pattern { return pattern }
        if let query { return query }
        if let url { return url }
        return description
    }

    /// Parse from a JSON string.
    static func parse(from json: String) -> ToolInput? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return ToolInput(
            command: dict["command"] as? String,
            description: dict["description"] as? String,
            filePath: (dict["file_path"] as? String) ?? (dict["path"] as? String),
            oldString: dict["old_string"] as? String,
            newString: dict["new_string"] as? String,
            content: dict["content"] as? String,
            pattern: dict["pattern"] as? String,
            query: dict["query"] as? String,
            url: dict["url"] as? String
        )
    }
}

// MARK: - Question (AskUserQuestion)

/// A question from Claude Code's AskUserQuestion tool.
struct Question: Sendable, Equatable, Identifiable {
    var id: String { text }

    let text: String
    let header: String?
    let options: [Option]
    let multiSelect: Bool

    struct Option: Sendable, Equatable, Identifiable {
        var id: String { label }
        let label: String
        let description: String?
    }

    /// Parse the questions array from an AskUserQuestion input JSON string.
    static func parseAll(from json: String) -> [Question]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questionsArr = dict["questions"] as? [[String: Any]]
        else { return nil }

        let parsed = questionsArr.compactMap { q -> Question? in
            guard let text = q["question"] as? String else { return nil }
            let header = q["header"] as? String
            let multiSelect = q["multiSelect"] as? Bool ?? false
            let options = (q["options"] as? [[String: Any]])?.compactMap { opt -> Option? in
                guard let label = opt["label"] as? String else { return nil }
                return Option(label: label, description: opt["description"] as? String)
            } ?? []
            return Question(text: text, header: header, options: options, multiSelect: multiSelect)
        }

        return parsed.isEmpty ? nil : parsed
    }
}
