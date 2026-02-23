import SwiftUI

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState
    @State private var inputText = ""

    var body: some View {
        Group {
            if let detail = store.selectedDetail {
                VStack(spacing: 0) {
                    DetailHeaderView(summary: detail.summary)

                    Divider()
                        .overlay(DS.Color.Border.subtle)

                    // Subagent panel (above message feed when subagents exist)
                    if !detail.subagents.isEmpty {
                        SubagentPanelView(subagents: detail.subagents)

                        Divider()
                            .overlay(DS.Color.Border.subtle)
                    }

                    // Message feed — StreamingFeedBridge isolates per-character
                    // streaming observation so the rest of SessionDetailView
                    // (header, panels, input bar) doesn't re-render on each token.
                    StreamingFeedBridge(messages: detail.messages)
                        .frame(maxHeight: .infinity)

                    // Live interactive panels (when connected)
                    if let request = store.pendingControlRequest,
                       store.connectionState.isConnected {
                        Divider()
                            .overlay(DS.Color.Border.subtle)

                        if request.toolName == "AskUserQuestion" {
                            // Question panel with selectable options
                            LiveQuestionPanel(request: request) { answers in
                                Task { await store.answerQuestion(answers: answers) }
                            } onReject: { message in
                                Task { await store.rejectToolUse(message: message) }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            // Standard tool approval panel
                            LiveApprovalPanel(request: request) {
                                Task { await store.approveToolUse() }
                            } onReject: { message in
                                Task { await store.rejectToolUse(message: message) }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    // Read-only pending interaction panel (when NOT connected)
                    if !store.connectionState.isConnected,
                       let pending = detail.summary.pendingInteraction {
                        Divider()
                            .overlay(DS.Color.Border.subtle)

                        PendingInteractionPanel(interaction: pending)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Input bar (only when connected interactively)
                    if store.connectionState.isConnected {
                        InputBarView(
                            text: $inputText,
                            isEnabled: !store.isStreaming && store.pendingControlRequest == nil,
                            onSend: { text in
                                Task { await store.sendMessage(text) }
                            }
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "sidebar.squares.right",
                    title: "Select a session",
                    description: "Choose a session from the list to view its details"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.Color.Surface.base)
        .onChange(of: uiState.selectedSessionId) { _, newId in
            if let id = newId {
                Task {
                    await store.loadDetail(for: id)
                }
            } else {
                store.clearDetail()
            }
        }
    }
}

// MARK: - Live Approval Panel
//
// Shown when the interactive session receives a control_request (tool permission).
// Unlike the read-only PendingInteractionPanel, this one has real Allow/Deny buttons.

private struct LiveApprovalPanel: View {
    let request: SessionStore.ControlRequest
    let onApprove: () -> Void
    let onReject: (String) -> Void

    @State private var borderPulse = false
    @State private var isExpanded = true
    @State private var rejectMessage = ""
    @State private var showRejectField = false

    private var accentColor: Color { DS.Color.Status.waitingDot }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing accent bar
            Rectangle()
                .fill(accentColor.opacity(borderPulse ? 0.6 : 0.25))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Header
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentColor)

                    Text("Approve: \(request.toolName)")
                        .font(DS.Typography.small)
                        .foregroundStyle(DS.Color.Text.secondary)

                    Spacer()

                    Button {
                        withAnimation(DS.Motion.fast) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Color.Text.tertiary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    // Tool input preview
                    toolInputPreview

                    // Reject message field (shown when user clicks Deny)
                    if showRejectField {
                        HStack(spacing: DS.Space.sm) {
                            TextField("Reason for rejection...", text: $rejectMessage)
                                .textFieldStyle(.plain)
                                .font(DS.Typography.caption)
                                .padding(.horizontal, DS.Space.sm)
                                .padding(.vertical, DS.Space.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                        .fill(DS.Color.Surface.overlay)
                                )

                            Button("Send") {
                                let msg = rejectMessage.isEmpty ? "User rejected this action" : rejectMessage
                                onReject(msg)
                                showRejectField = false
                                rejectMessage = ""
                            }
                            .font(DS.Typography.small)
                            .buttonStyle(.plain)
                            .foregroundStyle(DS.Color.Status.errorDot)
                        }
                    }
                }

                // Action buttons
                HStack(spacing: DS.Space.md) {
                    Spacer()

                    Button {
                        withAnimation(DS.Motion.fast) {
                            showRejectField.toggle()
                        }
                    } label: {
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                            Text("Deny")
                                .font(DS.Typography.small)
                        }
                        .foregroundStyle(DS.Color.Status.errorDot)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Color.Status.errorDot.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .strokeBorder(DS.Color.Status.errorDot.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Allow")
                                .font(DS.Typography.small)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Color.Status.activeDot)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(accentColor.opacity(0.04))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }

    @ViewBuilder
    private var toolInputPreview: some View {
        let json = request.inputJSON
        if !json.isEmpty && json != "{}" {
            // Parse known fields for rich display
            let parsed = ToolInput.parse(fromJSON: json)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let command = parsed?.command {
                    codeBlock(command)
                } else if let filePath = parsed?.filePath {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.Text.tertiary)
                        Text(filePath)
                            .font(DS.Typography.captionMono)
                            .foregroundStyle(DS.Color.Text.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    // Fallback: show raw JSON
                    codeBlock(String(json.prefix(300)))
                }

                if let oldStr = parsed?.oldString, let newStr = parsed?.newString {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        diffLine(prefix: "-", text: oldStr, color: DS.Color.Status.errorDot)
                        diffLine(prefix: "+", text: newStr, color: DS.Color.Status.activeDot)
                    }
                }
            }
        }
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(DS.Typography.mdCodeBlock)
            .foregroundStyle(DS.Color.Text.primary)
            .lineLimit(4)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Color.Surface.overlay)
            )
    }

    private func diffLine(prefix: String, text: String, color: Color) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(prefix)
                .font(DS.Typography.mdCodeBlock)
                .foregroundStyle(color)
                .frame(width: 12)
            Text(Formatters.truncate(text, to: 120))
                .font(DS.Typography.mdCodeBlock)
                .foregroundStyle(color.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(color.opacity(0.06))
        )
    }
}

// MARK: - Live Question Panel
//
// Shown when the interactive session receives an AskUserQuestion control_request.
// Displays each question with selectable option chips, an "Other" text input,
// and a Submit button. Supports both single-select and multi-select questions.

private struct LiveQuestionPanel: View {
    let request: SessionStore.ControlRequest
    let onAnswer: ([String: String]) -> Void
    let onReject: (String) -> Void

    @State private var borderPulse = false
    // Tracks selected options per question (keyed by question text)
    // For single-select: one label; for multi-select: Set of labels
    @State private var selections: [String: Set<String>] = [:]
    // "Other" text per question
    @State private var otherTexts: [String: String] = [:]
    // Whether "Other" is active per question
    @State private var otherActive: [String: Bool] = [:]

    private var accentColor: Color { DS.Color.Accent.secondary }

    private var questions: [Question] {
        Question.parseAll(from: request.inputJSON) ?? []
    }

    private var canSubmit: Bool {
        // Every question must have at least one selection (or "Other" text)
        for q in questions {
            let selected = selections[q.text] ?? []
            let hasOther = otherActive[q.text] == true && !(otherTexts[q.text]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if selected.isEmpty && !hasOther { return false }
        }
        return !questions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing accent bar
            Rectangle()
                .fill(accentColor.opacity(borderPulse ? 0.6 : 0.25))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: DS.Space.md) {
                // Header
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentColor)

                    Text("Claude is asking a question")
                        .font(DS.Typography.small)
                        .foregroundStyle(DS.Color.Text.secondary)

                    Spacer()
                }

                // Each question
                ForEach(questions) { question in
                    questionView(question)
                }

                // Action buttons
                HStack(spacing: DS.Space.md) {
                    Spacer()

                    Button {
                        onReject("User dismissed the question")
                    } label: {
                        Text("Skip")
                            .font(DS.Typography.small)
                            .foregroundStyle(DS.Color.Text.tertiary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.xs)
                    }
                    .buttonStyle(.plain)

                    Button(action: submit) {
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                            Text("Submit")
                                .font(DS.Typography.small)
                        }
                        .foregroundStyle(canSubmit ? .white : DS.Color.Text.quaternary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(canSubmit ? accentColor : DS.Color.Surface.overlay)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(accentColor.opacity(0.04))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }

    // MARK: - Question View

    @ViewBuilder
    private func questionView(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // Header tag
            if let header = question.header {
                Text(header.uppercased())
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Color.Text.tertiary)
                    .tracking(0.5)
            }

            // Question text
            Text(question.text)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.Text.primary)

            // Selectable option chips
            FlowLayout(spacing: DS.Space.xs) {
                ForEach(question.options) { option in
                    selectableChip(option, question: question)
                }

                // "Other" chip
                otherChip(question: question)
            }

            // "Other" text field (when active)
            if otherActive[question.text] == true {
                TextField("Type your answer...", text: otherBinding(for: question.text))
                    .textFieldStyle(.plain)
                    .font(DS.Typography.caption)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .fill(DS.Color.Surface.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                    )
            }

            if question.multiSelect {
                Text("Multiple selections allowed")
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Color.Text.quaternary)
            }
        }
    }

    // MARK: - Selectable Chip

    private func selectableChip(_ option: Question.Option, question: Question) -> some View {
        let isSelected = selections[question.text]?.contains(option.label) ?? false

        return Button {
            withAnimation(DS.Motion.fast) {
                toggleSelection(option.label, for: question)
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(option.label)
                    .font(DS.Typography.small)
                    .foregroundStyle(isSelected ? .white : DS.Color.Text.primary)
                if let desc = option.description {
                    Text(desc)
                        .font(DS.Typography.micro)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : DS.Color.Text.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isSelected ? accentColor : DS.Color.Surface.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(isSelected ? accentColor : DS.Color.Border.default, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - "Other" Chip

    private func otherChip(question: Question) -> some View {
        let isActive = otherActive[question.text] == true

        return Button {
            withAnimation(DS.Motion.fast) {
                otherActive[question.text] = !isActive
                if !isActive && !question.multiSelect {
                    // Clear option selections when switching to "Other" in single-select
                    selections[question.text] = []
                }
            }
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                Text("Other")
                    .font(DS.Typography.small)
            }
            .foregroundStyle(isActive ? .white : DS.Color.Text.secondary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isActive ? accentColor.opacity(0.7) : DS.Color.Surface.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(isActive ? accentColor : DS.Color.Border.default, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection Logic

    private func toggleSelection(_ label: String, for question: Question) {
        var current = selections[question.text] ?? []
        if question.multiSelect {
            if current.contains(label) {
                current.remove(label)
            } else {
                current.insert(label)
            }
        } else {
            // Single-select: replace
            current = current.contains(label) ? [] : [label]
            // Deactivate "Other" when selecting a predefined option
            otherActive[question.text] = false
        }
        selections[question.text] = current
    }

    // MARK: - Submit

    private func submit() {
        var answers: [String: String] = [:]
        for question in questions {
            if otherActive[question.text] == true,
               let text = otherTexts[question.text]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                answers[question.text] = text
            } else if let selected = selections[question.text], !selected.isEmpty {
                // Join multiple selections with comma for multiSelect
                answers[question.text] = selected.sorted().joined(separator: ", ")
            }
        }
        onAnswer(answers)
    }

    // MARK: - Helpers

    private func otherBinding(for questionText: String) -> Binding<String> {
        Binding(
            get: { otherTexts[questionText] ?? "" },
            set: { otherTexts[questionText] = $0 }
        )
    }
}

// MARK: - Pending Interaction Panel (read-only, for non-connected sessions)
//
// Renders different UIs based on the interaction type:
// - Tool approval: Shows tool name + input details + "Respond in VS Code" action
// - Question: Shows question text with option chips
// - Plan review: Shows plan summary + approve hint

private struct PendingInteractionPanel: View {
    let interaction: PendingInteraction
    @State private var borderPulse = false
    @State private var isExpanded = true

    private var accentColor: Color {
        switch interaction.type {
        case .toolApproval: DS.Color.Status.waitingDot
        case .question: DS.Color.Accent.secondary
        case .planReview: DS.Color.Accent.primary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing accent bar
            Rectangle()
                .fill(accentColor.opacity(borderPulse ? 0.6 : 0.25))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Header row with type icon, label, and expand toggle
                headerRow

                if isExpanded {
                    // Content based on interaction type
                    switch interaction.type {
                    case .toolApproval:
                        toolApprovalContent
                    case .question:
                        questionContent
                    case .planReview:
                        planReviewContent
                    }
                }

                // Action row
                actionRow
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(accentColor.opacity(0.04))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: headerIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accentColor)

            Text(headerLabel)
                .font(DS.Typography.small)
                .foregroundStyle(DS.Color.Text.secondary)

            Spacer()

            Button {
                withAnimation(DS.Motion.fast) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.Text.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var headerIcon: String {
        switch interaction.type {
        case .toolApproval: "exclamationmark.triangle.fill"
        case .question: "questionmark.circle.fill"
        case .planReview: "map.fill"
        }
    }

    private var headerLabel: String {
        switch interaction.type {
        case .toolApproval: "Waiting for approval: \(interaction.toolName)"
        case .question: "Claude is asking a question"
        case .planReview: "Plan ready for review"
        }
    }

    // MARK: - Tool Approval Content

    @ViewBuilder
    private var toolApprovalContent: some View {
        if let input = interaction.toolInput {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Primary detail (command, file path, etc.)
                if let command = input.command {
                    codeBlock(command)
                } else if let filePath = input.filePath {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.Text.tertiary)
                        Text(filePath)
                            .font(DS.Typography.captionMono)
                            .foregroundStyle(DS.Color.Text.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else if let pattern = input.pattern {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.Text.tertiary)
                        Text(pattern)
                            .font(DS.Typography.captionMono)
                            .foregroundStyle(DS.Color.Text.secondary)
                            .lineLimit(1)
                    }
                } else if let query = input.query {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.Text.tertiary)
                        Text(query)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.Text.secondary)
                            .lineLimit(2)
                    }
                }

                // Edit diff preview
                if let oldStr = input.oldString, let newStr = input.newString {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        diffLine(prefix: "-", text: oldStr, color: DS.Color.Status.errorDot)
                        diffLine(prefix: "+", text: newStr, color: DS.Color.Status.activeDot)
                    }
                }
            }
        }
    }

    // MARK: - Question Content

    @ViewBuilder
    private var questionContent: some View {
        if let questions = interaction.questions {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        if let header = question.header {
                            Text(header.uppercased())
                                .font(DS.Typography.micro)
                                .foregroundStyle(DS.Color.Text.tertiary)
                                .tracking(0.5)
                        }

                        Text(question.text)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.Text.primary)

                        // Option chips
                        FlowLayout(spacing: DS.Space.xs) {
                            ForEach(question.options) { option in
                                optionChip(option)
                            }
                        }

                        if question.multiSelect {
                            Text("Multiple selections allowed")
                                .font(DS.Typography.micro)
                                .foregroundStyle(DS.Color.Text.quaternary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Plan Review Content

    @ViewBuilder
    private var planReviewContent: some View {
        if let plan = interaction.planMarkdown {
            let preview = String(plan.prefix(500))
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(preview + (plan.count > 500 ? "..." : ""))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.Text.secondary)
                    .lineLimit(8)
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack {
            Spacer()

            Button {
                activateVSCode()
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("Respond in VS Code")
                        .font(DS.Typography.small)
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(accentColor.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Subviews

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(DS.Typography.mdCodeBlock)
            .foregroundStyle(DS.Color.Text.primary)
            .lineLimit(4)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Color.Surface.overlay)
            )
    }

    private func diffLine(prefix: String, text: String, color: Color) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(prefix)
                .font(DS.Typography.mdCodeBlock)
                .foregroundStyle(color)
                .frame(width: 12)
            Text(Formatters.truncate(text, to: 120))
                .font(DS.Typography.mdCodeBlock)
                .foregroundStyle(color.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(color.opacity(0.06))
        )
    }

    private func optionChip(_ option: Question.Option) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(option.label)
                .font(DS.Typography.small)
                .foregroundStyle(DS.Color.Text.primary)
            if let desc = option.description {
                Text(desc)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Color.Text.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.Surface.overlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.Border.default, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func activateVSCode() {
        if let vscode = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.microsoft.VSCode"
        }) {
            vscode.activate()
        }
    }
}

// MARK: - Streaming Feed Bridge
//
// This view exists solely to isolate @Observable property access.
// Only StreamingFeedBridge reads the high-frequency streaming properties
// (currentStreamingText, currentStreamingThinking, isStreaming), so only
// this subtree re-evaluates on every streaming token — not the entire
// SessionDetailView (header, panels, input bar).

struct StreamingFeedBridge: View {
    @Environment(SessionStore.self) private var store
    let messages: [ParsedMessage]

    var body: some View {
        MessageFeedView(
            messages: messages,
            isStreaming: store.isStreaming,
            streamingText: store.currentStreamingText,
            streamingThinking: store.currentStreamingThinking
        )
    }
}

// MARK: - ToolInput JSON Parsing Helper

private extension ToolInput {
    /// Parse a ToolInput from a raw JSON string (used by LiveApprovalPanel).
    static func parse(fromJSON json: String) -> ToolInput? {
        ToolInput.parse(from: json)
    }
}
