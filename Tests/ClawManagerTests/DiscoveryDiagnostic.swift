import Testing
import Foundation
@testable import ClawManager

@Suite("Discovery Diagnostic")
struct DiscoveryDiagnostic {
    @Test("Can access projects directory")
    func accessProjectsDir() {
        let dir = PathUtilities.projectsDir
        print("Projects dir: \(dir.path)")
        let exists = FileManager.default.fileExists(atPath: dir.path)
        print("Exists: \(exists)")
        #expect(exists)
    }

    @Test("Can list workspace directories")
    func listWorkspaceDirs() throws {
        let dir = PathUtilities.projectsDir
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let dirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        print("Found \(dirs.count) workspace directories")
        for d in dirs.prefix(5) {
            print("  \(d.lastPathComponent)")
        }
        #expect(dirs.count > 0)
    }

    @Test("Can find JSONL files in a workspace")
    func findJSONLFiles() throws {
        let dir = PathUtilities.projectsDir
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let dirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

        guard let firstDir = dirs.first else {
            Issue.record("No workspace dirs found")
            return
        }

        let workspaceEntries = try FileManager.default.contentsOfDirectory(
            at: firstDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        )

        print("Workspace: \(firstDir.lastPathComponent)")
        for entry in workspaceEntries {
            let name = entry.lastPathComponent
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            print("  \(name) (dir: \(isDir), isUUID: \(PathUtilities.isUUID(name.replacingOccurrences(of: ".jsonl", with: ""))))")
        }

        let jsonlFiles = workspaceEntries.filter { $0.lastPathComponent.hasSuffix(".jsonl") }
        print("Found \(jsonlFiles.count) JSONL files")
        #expect(jsonlFiles.count > 0 || workspaceEntries.contains(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }))
    }

    @Test("Can parse JSONL tail")
    func parseJSONLTail() throws {
        // Find the first real JSONL file
        let dir = PathUtilities.projectsDir
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let dirs = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

        var foundJSONL: URL?
        for workspace in dirs {
            let files = try FileManager.default.contentsOfDirectory(
                at: workspace,
                includingPropertiesForKeys: nil,
                options: []
            )
            if let jsonl = files.first(where: { $0.lastPathComponent.hasSuffix(".jsonl") }) {
                foundJSONL = jsonl
                break
            }
        }

        guard let jsonlURL = foundJSONL else {
            Issue.record("No JSONL files found anywhere")
            return
        }

        print("Parsing: \(jsonlURL.path)")
        let mtime = JSONLParser.lastModified(at: jsonlURL)
        print("mtime: \(String(describing: mtime))")

        let tail = try JSONLParser.readTail(at: jsonlURL, count: 10)
        print("Got \(tail.count) messages from tail")
        for msg in tail {
            print("  type=\(msg.type.rawValue) role=\(msg.role?.rawValue ?? "nil") content=\(msg.content.count) blocks")
        }
        #expect(tail.count > 0)
    }

    @Test("Full discovery pipeline")
    func fullDiscovery() async {
        let discovery = SessionDiscoveryService()
        let sessions = await discovery.discoverAll()
        print("Discovered \(sessions.count) sessions")
        for s in sessions.prefix(5) {
            print("  [\(s.status.rawValue)] \(s.projectName) (\(s.sessionId.prefix(8))...) mtime=\(s.lastActivity)")
        }
        #expect(sessions.count > 0)
    }
}
