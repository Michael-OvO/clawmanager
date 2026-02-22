import SwiftUI

struct ToolCallView: View {
    let id: String
    let name: String
    let inputJSON: String

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var cachedBrief: String?
    @State private var briefComputed = false

    private var toolIcon: String {
        switch name {
        case "Bash":          "terminal.fill"
        case "Read":          "doc.text.fill"
        case "Write":         "doc.fill"
        case "Edit":          "pencil.line"
        case "Grep", "Glob":  "magnifyingglass"
        case "Task":          "person.2.fill"
        case "WebSearch":     "globe"
        case "WebFetch":      "arrow.down.doc.fill"
        case "TodoWrite":     "checklist"
        default:              "wrench.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(DS.Motion.springSmooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.Text.tertiary)

                    Text(name)
                        .font(DS.Typography.captionMono)
                        .foregroundStyle(DS.Color.Text.secondary)

                    // Brief description from input
                    if let brief = cachedBrief {
                        Text(brief)
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
                .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .overlay(DS.Color.Border.subtle)
                    .padding(.horizontal, DS.Space.sm)

                ScrollView {
                    Text(inputJSON)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Color.Text.secondary)
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
                .stroke(DS.Color.Border.subtle, lineWidth: 1)
        )
        .trackHover($isHovered)
        .onAppear { computeBriefIfNeeded() }
        .onChange(of: inputJSON) { _, _ in computeBriefIfNeeded() }
    }

    /// Compute the brief description once and cache it, avoiding JSON deserialization on every body evaluation.
    private func computeBriefIfNeeded() {
        guard !briefComputed || !inputJSON.isEmpty else { return }
        briefComputed = true

        guard let data = inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            cachedBrief = nil
            return
        }

        if let cmd = json["command"] as? String {
            cachedBrief = Formatters.truncate(cmd, to: 40)
        } else if let path = json["file_path"] as? String {
            cachedBrief = (path as NSString).lastPathComponent
        } else if let pattern = json["pattern"] as? String {
            cachedBrief = Formatters.truncate(pattern, to: 30)
        } else if let desc = json["description"] as? String {
            cachedBrief = Formatters.truncate(desc, to: 40)
        } else {
            cachedBrief = nil
        }
    }
}
