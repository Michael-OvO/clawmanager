import Foundation

struct ClaudeProcess: Sendable {
    let pid: Int32
    let sessionId: String?
    let workspacePath: String?
    let isResumed: Bool
}

enum ProcessMonitorService {

    /// Find all running Claude CLI processes by parsing `ps aux` output.
    /// Runs the subprocess on a detached task to avoid blocking the cooperative thread pool.
    static func findClaudeProcesses() -> [ClaudeProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ClaudeProcess] = []

        for line in output.components(separatedBy: "\n") {
            guard line.contains("claude") &&
                  line.contains("--output-format") else {
                continue
            }

            let columns = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            guard columns.count >= 2, let pid = Int32(columns[1]) else { continue }

            let sessionId = extractArg(from: line, flag: "--resume")
                ?? extractArg(from: line, flag: "--session-id")

            results.append(ClaudeProcess(
                pid: pid,
                sessionId: sessionId,
                workspacePath: nil,
                isResumed: line.contains("--resume")
            ))
        }

        return results
    }

    /// Check if a process with given PID is alive.
    static func isProcessAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private static func extractArg(from cmd: String, flag: String) -> String? {
        guard let range = cmd.range(of: flag) else { return nil }
        let after = cmd[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !after.isEmpty else { return nil }
        let value = after.split(separator: " ", maxSplits: 1).first.map(String.init)
        if let v = value, PathUtilities.isUUID(v) {
            return v
        }
        return value
    }
}
