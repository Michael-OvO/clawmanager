import SwiftUI

struct DetailHeaderView: View {
    let summary: SessionSummary

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Status bar
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(summary.status.dotColor)
                .frame(width: 4, height: 28)
                .breathingGlow(color: summary.status.dotColor, isActive: summary.status == .active)

            // Session info
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Title row
                HStack {
                    Text(summary.projectName)
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Color.Text.primary)
                        .lineLimit(1)

                    Spacer()

                    // Copy session ID button
                    ActionButton(icon: "doc.on.doc", tooltip: "Copy Session ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.sessionId, forType: .string)
                    }
                }

                // Metadata row
                HStack(spacing: 0) {
                    metadataItem(text: summary.workspacePath, isMono: true)

                    if let model = summary.model {
                        separator
                        metadataItem(text: shortModel(model))
                    }

                    if let version = summary.cliVersion {
                        separator
                        metadataItem(text: "v\(version)")
                    }

                    if let branch = summary.gitBranch {
                        separator
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(branch)
                                .font(DS.Typography.captionMono)
                        }
                        .foregroundStyle(DS.Color.Text.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
    }

    private var separator: some View {
        Text("  |  ")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.Text.quaternary)
    }

    private func metadataItem(text: String, isMono: Bool = false) -> some View {
        Text(text)
            .font(isMono ? DS.Typography.captionMono : DS.Typography.caption)
            .foregroundStyle(DS.Color.Text.secondary)
            .lineLimit(1)
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("opus") { return "Opus 4" }
        if model.contains("sonnet") { return "Sonnet 4" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? DS.Color.Text.secondary : DS.Color.Text.tertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(isHovered ? DS.Color.Surface.elevated : .clear)
                )
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(tooltip)
    }
}
