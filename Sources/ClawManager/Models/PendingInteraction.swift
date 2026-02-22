import Foundation

struct PendingInteraction: Sendable, Equatable {
    enum InteractionType: String, Sendable {
        case permission
        case question
    }

    let type: InteractionType
    let toolUseId: String?
    let toolName: String?
    let toolInputJSON: String?
    let questionText: String?
}
