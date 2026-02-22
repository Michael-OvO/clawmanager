import SwiftUI

struct ToolResultView: View {
    let toolUseId: String
    let content: String
    let isError: Bool

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DS.Motion.springSmooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? DS.Color.Status.errorDot : DS.Color.Status.activeDot)

                    Text(isError ? "Error" : "Result")
                        .font(DS.Typography.caption)
                        .foregroundStyle(isError ? DS.Color.Status.errorText : DS.Color.Text.tertiary)

                    if !isExpanded {
                        Text(Formatters.truncate(content.replacingOccurrences(of: "\n", with: " "), to: 60))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.Text.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.sm + 2)
                .padding(.vertical, DS.Space.md - 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(DS.Color.Border.subtle)
                    .padding(.horizontal, DS.Space.sm)

                ScrollView {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isError ? DS.Color.Status.errorText : DS.Color.Text.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.sm)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(isHovered ? DS.Color.Surface.overlay : DS.Color.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(
                    isError ? DS.Color.Status.errorDot.opacity(0.2) : DS.Color.Border.subtle,
                    lineWidth: 1
                )
        )
        .trackHover($isHovered)
    }
}
