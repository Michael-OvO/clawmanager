import SwiftUI

struct ConnectionIndicator: View {
    let state: ConnectionState

    private var dotColor: Color {
        switch state {
        case .connected:       DS.Color.Status.activeDot
        case .connecting:      DS.Color.Status.waitingDot
        case .disconnected:    DS.Color.Text.quaternary
        case .error:           DS.Color.Status.errorDot
        case .terminated:      DS.Color.Text.quaternary
        }
    }

    private var label: String {
        state.label
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .breathingGlow(color: dotColor, isActive: state == .connected)

            Text(label)
                .font(DS.Typography.small)
                .foregroundStyle(DS.Color.Text.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(
            Capsule()
                .fill(DS.Color.Surface.overlay)
        )
        .overlay(
            Capsule()
                .stroke(DS.Color.Border.subtle, lineWidth: 1)
        )
    }
}
