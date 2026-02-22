import Foundation

enum Formatters {
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    static func timeAgo(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 0 { return "now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }

    static func shortId(_ id: String) -> String {
        String(id.prefix(8))
    }

    static func truncate(_ string: String, to length: Int) -> String {
        if string.count <= length { return string }
        return String(string.prefix(length - 1)) + "…"
    }

    static func formatTokenCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        return "\(count / 1000)k"
    }
}
