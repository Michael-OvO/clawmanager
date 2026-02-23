import SwiftUI

struct SessionRowView: View {
    let session: SessionSummary
    let isSelected: Bool

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var animating = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Status indicator bar
            statusBar

            // Content
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Row 1: Name + timestamp
                HStack(alignment: .firstTextBaseline) {
                    Text(session.projectName)
                        .font(DS.Typography.heading)
                        .foregroundStyle(DS.Color.Text.primary)
                        .lineLimit(1)

                    if let branch = session.gitBranch {
                        Text(branch)
                            .font(DS.Typography.captionMono)
                            .foregroundStyle(DS.Color.Text.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(Formatters.timeAgo(session.lastActivity))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .monospacedDigit()
                }

                // Row 2: Preview text or thinking indicator
                if session.status == .active {
                    HStack(spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.xxs) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(DS.Color.Status.activeDot)
                                    .frame(width: 4, height: 4)
                                    .scaleEffect(animating ? 1.0 : 0.4)
                                    .opacity(animating ? 1.0 : 0.2)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.15),
                                        value: animating
                                    )
                            }
                        }

                        Text("Thinking...")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.Status.activeText)
                            .italic()
                    }
                    .onAppear { animating = true }
                    .onDisappear { animating = false }
                } else {
                    Text(previewText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.secondary)
                        .lineLimit(1)
                }

                // Row 3: Metadata badges
                HStack(spacing: DS.Space.md - 4) {
                    if session.pendingInteraction != nil {
                        metadataBadge(
                            icon: "exclamationmark.triangle.fill",
                            text: session.pendingInteraction?.toolName ?? "Pending",
                            color: DS.Color.Status.waitingText
                        )
                    }

                    if let model = session.model {
                        metadataBadge(icon: "cpu", text: shortModel(model))
                    }

                    metadataBadge(
                        icon: "number",
                        text: Formatters.shortId(session.sessionId)
                    )

                    if session.subagentCount > 0 {
                        metadataBadge(
                            icon: "person.2",
                            text: "\(session.subagentCount)"
                        )
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .glassCard(isSelected: isSelected, isHovered: isHovered)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(DS.Motion.springInteractive, value: isPressed)
        .contentShape(Rectangle())
        .trackHover($isHovered)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs)
            .fill(session.status.dotColor)
            .frame(width: 3, height: 40)
            .breathingGlow(color: session.status.dotColor, isActive: session.status == .active)
            .pulseOpacity(isActive: session.status == .waiting)
            .opacity(session.status == .stale ? 0.6 : 1.0)
    }

    // MARK: - Helpers

    private var previewText: String {
        guard let last = session.lastMessages.last else { return "No messages yet" }
        if let tool = last.toolName { return "Used \(tool)" }
        if last.text.isEmpty { return "..." }
        return last.text
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model.components(separatedBy: "-").last ?? model
    }

    private func metadataBadge(icon: String, text: String, color: Color = DS.Color.Text.tertiary) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(DS.Typography.micro)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DS.Space.md - 4)
        .padding(.vertical, DS.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Color.Surface.elevated)
        )
    }
}
