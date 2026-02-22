import Foundation

enum PathUtilities {
    static var claudeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    static var projectsDir: URL {
        claudeDir.appendingPathComponent("projects")
    }

    static var ideDir: URL {
        claudeDir.appendingPathComponent("ide")
    }

    /// Demangle encoded workspace path back to absolute path.
    /// `-Users-michael-Documents-GitHub-Foo` → `/Users/michael/Documents/GitHub/Foo`
    /// Handles trailing hyphens from paths ending with special chars.
    static func demangleWorkspacePath(_ mangled: String) -> String {
        var cleaned = mangled
        // Remove trailing hyphen if present (from paths ending with special chars)
        if cleaned.hasSuffix("-") {
            cleaned = String(cleaned.dropLast())
        }
        guard cleaned.hasPrefix("-") else { return cleaned }
        return "/" + cleaned.dropFirst().replacingOccurrences(of: "-", with: "/")
    }

    /// Extract just the project name (last path component) from a workspace path.
    static func projectName(from workspacePath: String) -> String {
        (workspacePath as NSString).lastPathComponent
    }

    /// Validate UUID format: 8-4-4-4-12 hex chars.
    static func isUUID(_ string: String) -> Bool {
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }
}
