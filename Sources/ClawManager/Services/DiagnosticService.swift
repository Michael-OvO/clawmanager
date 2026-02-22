import Foundation

// MARK: - Diagnostic Service
//
// Provides two probing surfaces:
//
// 1. **Event log** (`/tmp/clawmanager_diag.jsonl`)
//    Append-only JSONL file recording timestamped events.
//    Grep for `"category":"tail"` or `"level":"error"` etc.
//
// 2. **State snapshot** (`/tmp/clawmanager_state.json`)
//    Periodically overwritten JSON file showing current app state.
//    Read anytime to see session counts, tail status, selected detail, etc.
//
// Usage from Claude Code CLI:
//    Read /tmp/clawmanager_state.json          → current state
//    Grep pattern="error" path="/tmp/clawmanager_diag.jsonl"  → errors
//    Bash: tail -20 /tmp/clawmanager_diag.jsonl               → recent events

enum Diag {

    // MARK: - File Paths

    static let logPath = "/tmp/clawmanager_diag.jsonl"
    static let statePath = "/tmp/clawmanager_state.json"

    // MARK: - Log Levels

    enum Level: String, Sendable {
        case info
        case warn
        case error
        case perf   // performance measurement
    }

    // MARK: - Categories

    enum Category: String, Sendable {
        case app        // startup, shutdown
        case discovery  // session discovery & refresh
        case detail     // detail loading
        case tail       // JSONL file tailing
        case state      // state snapshot writes
    }

    // MARK: - Logging

    /// Log a structured event to `/tmp/clawmanager_diag.jsonl`.
    /// Thread-safe via a serial queue.
    ///
    /// `data` uses `sending` to satisfy Swift 6 Sendability for the
    /// `DispatchQueue.async` closure without requiring `[String: any Sendable]`
    /// at every call site.
    nonisolated static func log(
        _ level: Level = .info,
        _ category: Category,
        _ message: String,
        data: sending [String: Any]? = nil
    ) {
        // Serialize the JSON line eagerly on the calling thread so the
        // `queue.async` closure only captures a Sendable `Data` value.
        var entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "level": level.rawValue,
            "cat": category.rawValue,
            "msg": message
        ]
        if let data {
            entry["data"] = data
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: entry, options: []),
              var line = String(data: jsonData, encoding: .utf8) else { return }
        line += "\n"

        guard let lineData = line.data(using: .utf8) else { return }

        queue.async {
            // Rotate if > 5 MB
            rotateIfNeeded()

            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                    try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: lineData)
            }
        }
    }

    // MARK: - State Snapshot

    /// Write a state snapshot to `/tmp/clawmanager_state.json`.
    /// Called from SessionStore on a periodic timer.
    nonisolated static func writeState(_ snapshot: StateSnapshot) {
        queue.async {
            guard let data = try? JSONEncoder.prettyDiag.encode(snapshot) else { return }
            try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
        }
    }

    // MARK: - Performance Measurement

    /// Measure execution time of a closure, logging the result.
    @discardableResult
    nonisolated static func measure<T>(
        _ category: Category,
        _ label: String,
        block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log(.perf, category, "\(label): \(String(format: "%.1f", elapsed))ms")
        return result
    }

    /// Returns the current time for manual perf measurement.
    /// Usage: `let t = Diag.now(); ... ; Diag.elapsed(t, .tail, "readAll")`
    nonisolated static func now() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    /// Log elapsed time since `start`.
    nonisolated static func elapsed(_ start: CFAbsoluteTime, _ category: Category, _ label: String) {
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log(.perf, category, "\(label): \(String(format: "%.1f", ms))ms")
    }

    // MARK: - Private

    private static let queue = DispatchQueue(label: "com.clawmanager.diag", qos: .utility)

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64,
              size > 5_000_000 else { return }
        // Keep last 1MB, discard the rest
        if let data = FileManager.default.contents(atPath: logPath) {
            let keepBytes = min(data.count, 1_000_000)
            let tail = data.suffix(keepBytes)
            try? tail.write(to: URL(fileURLWithPath: logPath), options: .atomic)
        }
    }
}

// MARK: - State Snapshot Model

struct StateSnapshot: Codable, Sendable {
    let timestamp: String
    let sessions: SessionStats
    let projects: Int
    let selectedSession: SelectedSessionInfo?
    let tail: TailInfo

    struct SessionStats: Codable, Sendable {
        let total: Int
        let active: Int
        let waiting: Int
        let idle: Int
        let stale: Int
    }

    struct SelectedSessionInfo: Codable, Sendable {
        let sessionId: String
        let project: String
        let status: String
        let messageCount: Int
        let hasPendingInteraction: Bool
        let pendingToolName: String?
    }

    struct TailInfo: Codable, Sendable {
        let active: Bool
        let path: String?
        let offsetBytes: UInt64
        let messagesTailed: Int
    }
}

// MARK: - JSON Encoder Extension

private extension JSONEncoder {
    static let prettyDiag: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
