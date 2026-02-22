import SwiftUI

struct LiveMessageRowView: View {
    let message: LiveMessage

    private var isUser: Bool { message.role == .user }
    private var borderColor: Color { isUser ? DS.Color.Accent.primary : DS.Color.Accent.secondary }
    private var roleLabel: String { isUser ? "You" : "Claude" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left border (matches MessageRowView)
            RoundedRectangle(cornerRadius: 1)
                .fill(borderColor)
                .frame(width: 2)
                .padding(.vertical, DS.Space.xxs)

            // Content
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Role label + streaming indicator
                HStack(spacing: DS.Space.sm) {
                    Text(roleLabel)
                        .font(DS.Typography.small)
                        .foregroundStyle(borderColor)

                    if !message.isComplete {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Spacer()

                    Text(Formatters.timeAgo(message.timestamp))
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.quaternary)
                }

                // Thinking block
                if !message.thinkingAccumulator.isEmpty {
                    ThinkingBlockView(text: message.thinkingAccumulator)
                }

                // Text content
                if !message.textAccumulator.isEmpty {
                    if isUser {
                        Text(message.textAccumulator)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.Text.primary)
                            .textSelection(.enabled)
                    } else {
                        MarkdownRenderer(text: message.textAccumulator)
                    }
                } else if !message.isComplete && message.thinkingAccumulator.isEmpty {
                    // Typing dots when no content yet
                    TypingIndicator()
                }

                // Tool calls
                ForEach(message.toolCalls) { toolCall in
                    ToolCallView(
                        id: toolCall.id,
                        name: toolCall.name,
                        inputJSON: toolCall.inputJson
                    )
                }
            }
            .padding(.leading, DS.Space.md)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.Color.Accent.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(dotOpacity(index: i))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func dotOpacity(index: Int) -> Double {
        let offset = Double(index) * 0.25
        let t = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.3 + 0.7 * sin(t * .pi)
    }
}
