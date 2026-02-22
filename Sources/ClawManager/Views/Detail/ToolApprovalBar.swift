import SwiftUI

struct ToolApprovalBar: View {
    let toolName: String
    let inputJSON: String
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExpanded = false
    @State private var borderPulse = false

    /// Convenience initializer from a LiveToolCall.
    init(toolCall: LiveToolCall, onApprove: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.toolName = toolCall.name
        self.inputJSON = toolCall.inputJson
        self.onApprove = onApprove
        self.onReject = onReject
    }

    /// Convenience initializer from a PendingInteraction (read-only sessions).
    init(interaction: PendingInteraction, onApprove: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.toolName = interaction.toolName ?? "Unknown"
        self.inputJSON = interaction.toolInputJSON ?? ""
        self.onApprove = onApprove
        self.onReject = onReject
    }

    private var isBash: Bool { toolName == "Bash" }

    private var toolIcon: String {
        switch toolName {
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

    /// Parsed tool input.
    private var parsedInput: [String: Any]? {
        guard let data = inputJSON.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The bash command string, if this is a Bash tool call.
    private var bashCommand: String? {
        guard isBash, let json = parsedInput else { return nil }
        return json["command"] as? String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing amber top border
            Rectangle()
                .fill(DS.Color.Status.waitingDot.opacity(borderPulse ? 0.6 : 0.3))
                .frame(height: 2)

            VStack(spacing: DS.Space.sm) {
                // Main row: icon + tool name + actions
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

                            Text(toolName)
                                .font(DS.Typography.captionMono)
                                .foregroundStyle(DS.Color.Text.secondary)
                        }

                        // For non-Bash tools, show the brief description inline
                        if !isBash, let brief = briefInput {
                            Text(brief)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.Text.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Expand/collapse details
                    if !inputJSON.isEmpty {
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

                // Bash command preview — always visible (the whole point of the bar)
                if let cmd = bashCommand {
                    bashCommandPreview(cmd)
                }

                // Edit preview — show old/new strings or file path
                if toolName == "Edit" || toolName == "Write" {
                    filePreview
                }

                // Expanded JSON details (for inspecting the full raw input)
                if isExpanded {
                    ScrollView {
                        Text(inputJSON)
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

    // MARK: - Bash Command Preview

    @ViewBuilder
    private func bashCommandPreview(_ command: String) -> some View {
        HStack(spacing: 0) {
            Text("$")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.Color.Accent.primary.opacity(0.6))
                .padding(.trailing, DS.Space.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DS.Color.Text.primary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: DS.Space.sm)

            CopyButton(text: command)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.Border.subtle, lineWidth: 1)
        )
    }

    // MARK: - File Preview (Edit/Write)

    @ViewBuilder
    private var filePreview: some View {
        if let json = parsedInput, let path = json["file_path"] as? String {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: toolName == "Edit" ? "pencil.line" : "doc.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.Text.tertiary)

                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DS.Color.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: DS.Space.sm)

                CopyButton(text: path)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Color.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.Border.subtle, lineWidth: 1)
            )
        }
    }

    // MARK: - Brief Input (for other tools)

    private var briefInput: String? {
        guard let json = parsedInput else { return nil }
        if let cmd = json["command"] as? String { return Formatters.truncate(cmd, to: 60) }
        if let path = json["file_path"] as? String { return (path as NSString).lastPathComponent }
        if let pattern = json["pattern"] as? String { return Formatters.truncate(pattern, to: 40) }
        if let desc = json["description"] as? String { return Formatters.truncate(desc, to: 60) }
        return nil
    }
}
