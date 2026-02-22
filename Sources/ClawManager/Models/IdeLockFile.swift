import Foundation

struct IdeLockFile: Codable, Sendable {
    let pid: Int32
    let workspaceFolders: [String]
    let ideName: String
    let transport: String
    let authToken: String
    let runningInWindows: Bool
}
