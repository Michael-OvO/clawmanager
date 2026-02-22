import SwiftUI

struct ToolApprovalBar: View {
    let toolCall: LiveToolCall
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExpanded = false
    @State private var borderPulse = false

    private var toolIcon: String {
        switch toolCall.name {
        case "Bash":          "terminal.fill"
        case "Read":          "doc.text.fill"
        case "Write":         "doc.fill"
        case "Edit":          "pencil.line"
        case "Grep", "Glob":  "magnifyingglass"
        case "Task":          "person.2.fill"
        case "WebSearch":     "globe"
        case "WebFetch":      "arrow.down.doc.fill"
        default:              "wrench.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing amber top border
            Rectangle()
                .fill(DS.Color.Status.waitingDot.opacity(borderPulse ? 0.6 : 0.3))
                .frame(height: 2)

            VStack(spacing: DS.Space.sm) {
                // Main row
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.Status.waitingDot)

                    // Tool info
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: toolIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Color.Text.tertiary)

                            Text(toolCall.name)
                                .font(DS.Typography.captionMono)
                                .foregroundStyle(DS.Color.Text.secondary)
                        }

                        if let brief = briefInput {
                            Text(brief)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.Text.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Expand/collapse details
                    if !toolCall.inputJson.isEmpty {
                        Button {
                            withAnimation(DS.Motion.springSmooth) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.Text.quaternary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }

                    // Action buttons
                    Button(action: onReject) {
                        Text("Deny")
                            .font(DS.Typography.small)
                            .foregroundStyle(DS.Color.Status.errorText)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.xs + 2)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .fill(DS.Color.Status.errorBg)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        Text("Allow")
                            .font(DS.Typography.small)
                            .foregroundStyle(DS.Color.Status.activeText)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.xs + 2)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .fill(DS.Color.Status.activeBg)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }

                // Expanded JSON details
                if isExpanded {
                    ScrollView {
                        Text(toolCall.inputJson)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DS.Color.Text.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.sm)
                    }
                    .frame(maxHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Color.Surface.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.Border.subtle, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(DS.Color.Status.waitingDot.opacity(0.06))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }

    private var briefInput: String? {
        guard let data = toolCall.inputJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let cmd = json["command"] as? String { return Formatters.truncate(cmd, to: 60) }
        if let path = json["file_path"] as? String { return (path as NSString).lastPathComponent }
        if let pattern = json["pattern"] as? String { return Formatters.truncate(pattern, to: 40) }
        if let desc = json["description"] as? String { return Formatters.truncate(desc, to: 60) }
        return nil
    }
}
