import SwiftUI

enum SessionStatus: String, CaseIterable, Identifiable, Sendable {
    case active
    case waiting
    case idle
    case stale
    case error

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var dotColor: Color {
        switch self {
        case .active:  DS.Color.Status.activeDot
        case .waiting: DS.Color.Status.waitingDot
        case .idle:    DS.Color.Status.idleDot
        case .stale:   DS.Color.Status.staleDot
        case .error:   DS.Color.Status.errorDot
        }
    }

    var bgColor: Color {
        switch self {
        case .active:  DS.Color.Status.activeBg
        case .waiting: DS.Color.Status.waitingBg
        case .idle:    DS.Color.Status.idleBg
        case .stale:   DS.Color.Status.staleBg
        case .error:   DS.Color.Status.errorBg
        }
    }

    var textColor: Color {
        switch self {
        case .active:  DS.Color.Status.activeText
        case .waiting: DS.Color.Status.waitingText
        case .idle:    DS.Color.Status.idleText
        case .stale:   DS.Color.Status.staleText
        case .error:   DS.Color.Status.errorText
        }
    }

    var systemImage: String {
        switch self {
        case .active:  "circle.fill"
        case .waiting: "exclamationmark.triangle.fill"
        case .idle:    "moon.fill"
        case .stale:   "clock"
        case .error:   "xmark.circle.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .waiting: 0
        case .active:  1
        case .idle:    2
        case .stale:   3
        case .error:   4
        }
    }
}
