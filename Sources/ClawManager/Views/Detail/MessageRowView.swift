import SwiftUI

struct MessageRowView: View {
    let message: ParsedMessage

    @State private var isHovered = false

    private var isUser: Bool { message.role == .user }
    private var borderColor: Color { isUser ? DS.Color.Accent.primary : DS.Color.Accent.secondary }
    private var roleLabel: String { isUser ? "You" : "Claude" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left border
            RoundedRectangle(cornerRadius: 1)
                .fill(borderColor)
                .frame(width: 2)
                .padding(.vertical, DS.Space.xxs)

            // Content
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Sender label + timestamp + copy button
                HStack(spacing: DS.Space.sm) {
                    Text(roleLabel)
                        .font(DS.Typography.small)
                        .foregroundStyle(borderColor)

                    Spacer()

                    if isHovered {
                        CopyButton(text: copyableText, label: "Copy")
                            .transition(.opacity)
                    }

                    if let ts = message.timestamp {
                        Text(Formatters.timeAgo(ts))
                            .font(DS.Typography.micro)
                            .foregroundStyle(DS.Color.Text.quaternary)
                    }
                }

                // Content blocks (index-based IDs for stable identity)
                ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                    contentBlockView(block)
                }
            }
            .padding(.leading, DS.Space.md)
        }
        .contentShape(Rectangle())
        .trackHover($isHovered)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyableText, forType: .string)
            } label: {
                Label("Copy Message", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: MessageContent) -> some View {
        switch block {
        case .text(let text):
            if isUser {
                Text(text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.Text.primary)
                    .textSelection(.enabled)
            } else {
                MarkdownRenderer(text: text)
            }

        case .thinking(let text):
            ThinkingBlockView(text: text)

        case .toolUse(let id, let name, let inputJSON):
            ToolCallView(id: id, name: name, inputJSON: inputJSON)

        case .toolResult(let toolUseId, let content, let isError):
            ToolResultView(toolUseId: toolUseId, content: content, isError: isError)
        }
    }

    /// Extracts all text content from the message for clipboard copying.
    private var copyableText: String {
        message.content.compactMap { block in
            switch block {
            case .text(let text): text
            case .thinking(let text): text
            case .toolUse(_, let name, let input): "[\(name)] \(input)"
            case .toolResult(_, let content, _): content
            }
        }
        .joined(separator: "\n\n")
    }
}
