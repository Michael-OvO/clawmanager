import SwiftUI

struct StatusFilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let dotColor: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }

                Text(label)
                    .font(DS.Typography.small)
                    .foregroundStyle(isSelected ? selectedTextColor : DS.Color.Text.tertiary)

                if count > 0 {
                    Text("\(count)")
                        .font(DS.Typography.micro)
                        .foregroundStyle(isSelected ? selectedTextColor : DS.Color.Text.secondary)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(isSelected ? selectedBgColor.opacity(0.25) : DS.Color.Surface.base.opacity(0.6))
                        )
                }
            }
            .padding(.horizontal, DS.Space.sm + 2)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isSelected ? selectedBgColor : (isHovered ? DS.Color.Surface.overlay.opacity(0.5) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(
                        isSelected ? (dotColor ?? DS.Color.Accent.primary).opacity(0.3) : DS.Color.Border.subtle,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }

    private var selectedTextColor: Color {
        dotColor.map { _ in
            // Use the status text color based on dot color
            if dotColor == DS.Color.Status.activeDot { return DS.Color.Status.activeText }
            if dotColor == DS.Color.Status.waitingDot { return DS.Color.Status.waitingText }
            if dotColor == DS.Color.Status.idleDot { return DS.Color.Status.idleText }
            if dotColor == DS.Color.Status.staleDot { return DS.Color.Status.staleText }
            if dotColor == DS.Color.Status.errorDot { return DS.Color.Status.errorText }
            return DS.Color.Text.primary
        } ?? DS.Color.Text.primary
    }

    private var selectedBgColor: Color {
        if dotColor == DS.Color.Status.activeDot { return DS.Color.Status.activeBg }
        if dotColor == DS.Color.Status.waitingDot { return DS.Color.Status.waitingBg }
        if dotColor == DS.Color.Status.idleDot { return DS.Color.Status.idleBg }
        if dotColor == DS.Color.Status.staleDot { return DS.Color.Status.staleBg }
        if dotColor == DS.Color.Status.errorDot { return DS.Color.Status.errorBg }
        return DS.Color.Accent.primaryMuted
    }
}
