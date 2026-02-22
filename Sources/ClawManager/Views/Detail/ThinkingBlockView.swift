import SwiftUI

struct ThinkingBlockView: View {
    let text: String

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
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.Status.idleDot)

                    Text("Thinking...")
                        .font(DS.Typography.caption)
                        .italic()
                        .foregroundStyle(DS.Color.Status.idleDot)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.sm + 2)
                .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(DS.Color.Border.subtle)
                    .padding(.horizontal, DS.Space.sm)

                ScrollView {
                    Text(text)
                        .font(DS.Typography.body)
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
                .fill(isHovered ? DS.Color.Surface.overlay : DS.Color.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.Border.default, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .trackHover($isHovered)
    }
}
