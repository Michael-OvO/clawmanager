import SwiftUI

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            // Active indicator bar
            if project.activeSessionCount > 0 {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Color.Accent.primary)
                    .frame(width: 2, height: 20)
            }

            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(
                    project.activeSessionCount > 0
                        ? DS.Color.Accent.primary
                        : DS.Color.Text.tertiary
                )

            // Project name
            Text(project.name)
                .font(DS.Typography.caption)
                .foregroundStyle(
                    isSelected || project.activeSessionCount > 0
                        ? DS.Color.Text.primary
                        : DS.Color.Text.secondary
                )
                .lineLimit(1)

            Spacer()

            // Session count
            Text("\(project.sessionCount)")
                .font(DS.Typography.micro)
                .foregroundStyle(DS.Color.Text.quaternary)
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(isSelected ? DS.Color.Accent.primaryMuted : (isHovered ? DS.Color.Surface.overlay.opacity(0.4) : .clear))
        )
        .contentShape(Rectangle())
        .trackHover($isHovered)
    }
}
