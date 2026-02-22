import Foundation

struct Project: Identifiable, Sendable, Equatable {
    var id: String { mangledPath }

    let name: String
    let workspacePath: String
    let mangledPath: String
    var sessionCount: Int
    var activeSessionCount: Int
}
