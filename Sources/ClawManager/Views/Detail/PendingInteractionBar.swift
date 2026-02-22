import SwiftUI

struct PendingInteractionBar: View {
    let interaction: PendingInteraction

    @State private var borderPulse = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.Color.Status.waitingDot)

            // Description
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(interactionTitle)
                    .font(DS.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.Color.Status.waitingText)

                if let question = interaction.questionText {
                    Text(Formatters.truncate(question, to: 80))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.secondary)
                }
            }

            Spacer()

            // Status label
            Text("Waiting in terminal")
                .font(DS.Typography.small)
                .foregroundStyle(DS.Color.Text.tertiary)
        }
        .padding(.horizontal, DS.Space.xl)
        .frame(height: 56)
        .background(DS.Color.Status.waitingDot.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Color.Status.waitingDot.opacity(borderPulse ? 0.5 : 0.3))
                .frame(height: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }

    private var interactionTitle: String {
        switch interaction.type {
        case .question:
            "Question pending"
        case .permission:
            "Tool approval required: \(interaction.toolName ?? "Unknown")"
        }
    }
}
