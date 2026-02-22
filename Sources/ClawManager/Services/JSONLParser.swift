import Foundation

enum JSONLParser {

    // MARK: - Public API

    /// Read the last N lines of a JSONL file efficiently via reverse file reading.
    static func readTail(at url: URL, count: Int = 40) throws -> [ParsedMessage] {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else { return [] }

        let chunkSize: UInt64 = 8192
        var linesFound: [String] = []
        var position = fileSize
        var remainder = ""

        while linesFound.count < count && position > 0 {
            let readSize = min(chunkSize, position)
            position -= readSize
            fileHandle.seek(toFileOffset: position)

            guard let data = fileHandle.readData(ofLength: Int(readSize)) as Data?,
                  let chunk = String(data: data, encoding: .utf8) else { break }

            let combined = chunk + remainder
            var lines = combined.components(separatedBy: "\n")
            remainder = lines.removeFirst()

            for line in lines.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                linesFound.insert(trimmed, at: 0)
                if linesFound.count >= count { break }
            }
        }

        if !remainder.trimmingCharacters(in: .whitespaces).isEmpty && linesFound.count < count {
            linesFound.insert(remainder.trimmingCharacters(in: .whitespaces), at: 0)
        }

        return linesFound.suffix(count).compactMap { parseLine($0) }
    }

    /// Read the first N lines of a JSONL file efficiently (forward reading).
    static func readHead(at url: URL, count: Int = 5) throws -> [ParsedMessage] {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let chunkSize = 4096
        var linesFound: [String] = []
        var remainder = ""

        while linesFound.count < count {
            guard let data = fileHandle.readData(ofLength: chunkSize) as Data?,
                  !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else { break }

            let combined = remainder + chunk
            var lines = combined.components(separatedBy: "\n")
            remainder = lines.removeLast()

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                linesFound.append(trimmed)
                if linesFound.count >= count { break }
            }
        }

        if linesFound.count < count && !remainder.trimmingCharacters(in: .whitespaces).isEmpty {
            linesFound.append(remainder.trimmingCharacters(in: .whitespaces))
        }

        return linesFound.prefix(count).compactMap { parseLine($0) }
    }

    /// Count lines in a JSONL file without parsing them.
    static func lineCount(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        return data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            var count = 0
            let newline = UInt8(ascii: "\n")
            for i in 0..<buffer.count {
                if base[i] == newline { count += 1 }
            }
            // If file doesn't end with newline but has content, count the last line
            if buffer.count > 0 && base[buffer.count - 1] != newline { count += 1 }
            return count
        }
    }

    /// Read all messages from a JSONL file (for detail view).
    static func readAll(at url: URL) throws -> [ParsedMessage] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }

        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
    }

    /// Get file modification date.
    static func lastModified(at url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    // MARK: - Pending Interaction Detection

    /// Detect pending interactions: unanswered tool_use blocks in the last assistant message.
    static func detectPendingInteraction(in messages: [ParsedMessage]) -> PendingInteraction? {
        guard let lastAssistantIdx = messages.lastIndex(where: { $0.type == .assistant }) else {
            return nil
        }

        let assistant = messages[lastAssistantIdx]

        let toolUses: [(id: String, name: String, inputJSON: String)] = assistant.content.compactMap {
            if case .toolUse(let id, let name, let input) = $0 {
                return (id, name, input)
            }
            return nil
        }

        guard !toolUses.isEmpty else { return nil }

        // Check which tool_use IDs have been answered by subsequent tool_result blocks
        var answered = Set<String>()
        let subsequentMessages = messages.suffix(from: messages.index(after: lastAssistantIdx))
        for msg in subsequentMessages where msg.type == .user {
            for block in msg.content {
                if case .toolResult(let toolUseId, _, _) = block {
                    answered.insert(toolUseId)
                }
            }
        }

        // Find first unanswered tool_use
        guard let pending = toolUses.first(where: { !answered.contains($0.id) }) else {
            return nil
        }

        let isQuestion = pending.name == "AskUserQuestion"
        let questionText: String? = isQuestion ? extractQuestionText(from: pending.inputJSON) : nil

        return PendingInteraction(
            type: isQuestion ? .question : .permission,
            toolUseId: pending.id,
            toolName: pending.name,
            toolInputJSON: pending.inputJSON,
            questionText: questionText
        )
    }

    // MARK: - Preview Extraction

    /// Extract the last N user/assistant message previews.
    static func extractPreviews(from messages: [ParsedMessage], count: Int = 4) -> [MessagePreview] {
        messages
            .filter { $0.type == .user || $0.type == .assistant }
            .suffix(count)
            .map { msg in
                let textContent = msg.content.compactMap { block -> String? in
                    if case .text(let t) = block { return t }
                    return nil
                }.joined(separator: " ")

                let toolName = msg.content.compactMap { block -> String? in
                    if case .toolUse(_, let name, _) = block { return name }
                    return nil
                }.first

                return MessagePreview(
                    role: msg.role?.rawValue ?? msg.type.rawValue,
                    text: Formatters.truncate(textContent, to: 200),
                    toolName: toolName,
                    timestamp: msg.timestamp
                )
            }
    }

    /// Extract metadata (slug, gitBranch, version) from parsed messages.
    static func extractMetadata(from messages: [ParsedMessage]) -> (slug: String?, gitBranch: String?, version: String?, model: String?) {
        for msg in messages.reversed() {
            if msg.slug != nil || msg.gitBranch != nil || msg.version != nil || msg.model != nil {
                return (msg.slug, msg.gitBranch, msg.version, msg.model)
            }
        }
        return (nil, nil, nil, nil)
    }

    // MARK: - Line Parsing

    static func parseLine(_ line: String) -> ParsedMessage? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = json["type"] as? String else {
            return nil
        }

        let msgType = ParsedMessage.MessageType(rawValue: typeStr) ?? .unknown
        guard msgType != .unknown else { return nil }

        let timestamp = (json["timestamp"] as? String).flatMap { Formatters.parseISO8601($0) }
        let uuid = json["uuid"] as? String ?? UUID().uuidString

        switch msgType {
        case .user, .assistant:
            let msg = json["message"] as? [String: Any] ?? [:]
            let role = (msg["role"] as? String).flatMap { ParsedMessage.MessageRole(rawValue: $0) }
            let content = parseContent(msg["content"])
            let model = msg["model"] as? String

            return ParsedMessage(
                id: uuid, type: msgType, timestamp: timestamp,
                role: role, content: content, model: model,
                slug: json["slug"] as? String,
                gitBranch: json["gitBranch"] as? String,
                version: json["version"] as? String,
                sessionId: json["sessionId"] as? String,
                cwd: json["cwd"] as? String
            )

        case .progress, .queueOperation, .fileHistorySnapshot, .system:
            return ParsedMessage(
                id: uuid, type: msgType, timestamp: timestamp,
                role: nil, content: [], model: nil,
                slug: json["slug"] as? String,
                gitBranch: json["gitBranch"] as? String,
                version: json["version"] as? String,
                sessionId: json["sessionId"] as? String,
                cwd: json["cwd"] as? String
            )

        case .unknown:
            return nil
        }
    }

    // MARK: - Content Parsing

    private static func parseContent(_ raw: Any?) -> [MessageContent] {
        if let str = raw as? String {
            return [.text(str)]
        }

        guard let arr = raw as? [[String: Any]] else { return [] }

        return arr.compactMap { block in
            guard let type = block["type"] as? String else { return nil }

            switch type {
            case "text":
                guard let text = block["text"] as? String else { return nil }
                return .text(text)

            case "thinking":
                let thinking = block["thinking"] as? String ?? ""
                return .thinking(thinking)

            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                let input = block["input"] ?? [:]
                let inputJSON: String
                if let inputData = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
                   let inputStr = String(data: inputData, encoding: .utf8) {
                    inputJSON = inputStr
                } else {
                    inputJSON = "{}"
                }
                return .toolUse(id: id, name: name, inputJSON: inputJSON)

            case "tool_result":
                guard let toolUseId = block["tool_use_id"] as? String else { return nil }
                let content: String = {
                    if let s = block["content"] as? String { return s }
                    if let arr = block["content"] as? [[String: Any]] {
                        return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    return ""
                }()
                let isError = block["is_error"] as? Bool ?? false
                return .toolResult(toolUseId: toolUseId, content: content, isError: isError)

            default:
                return nil
            }
        }
    }

    // MARK: - Helpers

    private static func extractQuestionText(from inputJSON: String) -> String? {
        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["question"] as? String
    }
}
