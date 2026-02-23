import SwiftUI

/// Displays a completed thinking block from Claude's extended thinking.
///
/// Collapsed by default, showing a summary line with word count.
/// Expands to reveal the full reasoning text in a scrollable container.
struct ThinkingBlockView: View {
    let text: String

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var wordCount = 0

    private var thinkingColor: Color { DS.Color.Status.idleDot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand/collapse
            Button {
                withAnimation(DS.Motion.springSmooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(thinkingColor)

                    Text("Thought")
                        .font(DS.Typography.small)
                        .foregroundStyle(thinkingColor)

                    Text("·")
                        .foregroundStyle(DS.Color.Text.quaternary)

                    Text("\(wordCount) words")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.quaternary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.sm + 2)
                .padding(.vertical, DS.Space.xs + 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(thinkingColor.opacity(0.15))
                    .padding(.horizontal, DS.Space.sm)

                ScrollView {
                    Text(text)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.sm)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(thinkingColor.opacity(isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(thinkingColor.opacity(0.12), lineWidth: 1)
        )
        .trackHover($isHovered)
        .onAppear { wordCount = text.split(separator: " ").count }
    }
}
