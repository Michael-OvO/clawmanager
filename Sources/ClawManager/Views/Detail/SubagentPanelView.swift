import SwiftUI

struct SubagentPanelView: View {
    let subagents: [SubagentSummary]

    @State private var isExpanded = false

    /// Estimated height of one collapsed SubagentRowView (~72pt)
    /// plus inter-row spacing (xs = 4pt), with list padding (sm = 8pt each side).
    /// Extra bottom breathing room for small counts (tapers to 0 at 4+).
    private var adaptiveMaxHeight: CGFloat {
        let rowHeight: CGFloat = 72
        let gap = DS.Space.xs
        let listPadding = DS.Space.sm * 2
        let extraBottom = max(0, CGFloat(4 - subagents.count)) * DS.Space.md
        let contentHeight = CGFloat(subagents.count) * rowHeight
            + CGFloat(max(subagents.count - 1, 0)) * gap
            + listPadding
            + extraBottom
        return min(contentHeight, 360)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(DS.Motion.springSmooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.Accent.secondary)

                    Text("Subagents")
                        .font(DS.Typography.small)
                        .foregroundStyle(DS.Color.Text.secondary)

                    Text("\(subagents.count)")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Accent.secondary)
                        .padding(.horizontal, DS.Space.xs + 2)
                        .padding(.vertical, DS.Space.xxs)
                        .background(
                            Capsule().fill(DS.Color.Accent.secondaryMuted)
                        )

                    let completed = subagents.filter(\.isCompleted).count
                    if completed < subagents.count {
                        Text("\(completed)/\(subagents.count) done")
                            .font(DS.Typography.micro)
                            .foregroundStyle(DS.Color.Status.activeText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(DS.Color.Border.subtle)

                ScrollView {
                    VStack(spacing: DS.Space.xs) {
                        ForEach(subagents) { subagent in
                            SubagentRowView(subagent: subagent)
                        }
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: adaptiveMaxHeight)
            }
        }
        .background(DS.Color.Surface.raised)
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: DS.Radius.lg,
            bottomTrailingRadius: DS.Radius.lg
        ))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

// MARK: - Subagent Row

private struct SubagentRowView: View {
    let subagent: SubagentSummary

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var loadedMessages: [ParsedMessage]?
    @State private var isLoading = false
    @State private var showFullSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary row
            Button {
                if isExpanded {
                    withAnimation(DS.Motion.springSmooth) {
                        isExpanded = false
                    }
                } else {
                    // Start loading before animating open
                    if loadedMessages == nil {
                        isLoading = true
                        Task.detached(priority: .userInitiated) { [path = subagent.jsonlPath] in
                            let url = URL(fileURLWithPath: path)
                            let messages = (try? JSONLParser.readAll(at: url)) ?? []
                            await MainActor.run {
                                loadedMessages = messages
                                isLoading = false
                                withAnimation(DS.Motion.springSmooth) {
                                    isExpanded = true
                                }
                            }
                        }
                    } else {
                        withAnimation(DS.Motion.springSmooth) {
                            isExpanded = true
                        }
                    }
                }
            } label: {
                summaryLabel
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider().overlay(DS.Color.Border.subtle)
                    .padding(.horizontal, DS.Space.sm)

                if let messages = loadedMessages {
                    expandedContent(messages: messages)
                }
            } else if isLoading {
                HStack(spacing: DS.Space.sm) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Loading messages...")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.tertiary)
                    Spacer()
                }
                .padding(.vertical, DS.Space.sm)
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
    }

    private var summaryLabel: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Circle()
                .fill(subagent.isCompleted ? DS.Color.Status.activeDot : DS.Color.Status.waitingDot)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("agent-\(subagent.agentId)")
                        .font(DS.Typography.captionMono)
                        .foregroundStyle(DS.Color.Text.secondary)

                    Spacer()

                    Text(Formatters.timeAgo(subagent.lastActivity))
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.quaternary)
                }

                Text(subagent.taskDescription)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.Text.tertiary)
                    .lineLimit(2)

                HStack(spacing: DS.Space.xs) {
                    metaChip(icon: "text.bubble", text: "\(subagent.messageCount) msgs")

                    metaChip(
                        icon: subagent.isCompleted ? "checkmark.circle" : "clock",
                        text: subagent.isCompleted ? "Done" : "Running",
                        color: subagent.isCompleted ? DS.Color.Status.activeText : DS.Color.Status.waitingText
                    )
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(DS.Color.Text.quaternary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .padding(.top, 4)
        }
        .padding(DS.Space.sm)
    }

    /// Maximum messages to show inline before offering "View all"
    private static let inlineMessageLimit = 6

    @ViewBuilder
    private func expandedContent(messages: [ParsedMessage]) -> some View {
        let visible = messages.filter { $0.type == .user || $0.type == .assistant }

        if visible.isEmpty {
            Text("No messages")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.Text.tertiary)
                .padding(DS.Space.md)
        } else {
            // Tool summary from loaded messages
            let tools = Set(messages.flatMap { msg in
                msg.content.compactMap { block -> String? in
                    if case .toolUse(_, let name, _) = block { return name }
                    return nil
                }
            }).sorted()

            let preview = Array(visible.suffix(Self.inlineMessageLimit))
            let hasMore = visible.count > Self.inlineMessageLimit

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                if !tools.isEmpty {
                    toolsSummary(tools: tools)
                }

                if hasMore {
                    Button {
                        showFullSheet = true
                    } label: {
                        Text("View all \(visible.count) messages...")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.Accent.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.sm)
                }

                ForEach(preview) { msg in
                    MessageRowView(message: msg)
                }
            }
            .padding(DS.Space.sm)
            .sheet(isPresented: $showFullSheet) {
                SubagentFullSheetView(
                    agentId: subagent.agentId,
                    messages: visible,
                    tools: tools
                )
            }
        }
    }

    private func toolsSummary(tools: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Tools used")
                .font(DS.Typography.micro)
                .foregroundStyle(DS.Color.Text.quaternary)

            FlowLayout(spacing: DS.Space.xs) {
                ForEach(tools, id: \.self) { tool in
                    Text(tool)
                        .font(DS.Typography.microMono)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(DS.Color.Surface.elevated)
                        )
                }
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
    }

    private func metaChip(icon: String, text: String, color: Color = DS.Color.Text.tertiary) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(DS.Typography.micro)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Full Conversation Sheet

private struct SubagentFullSheetView: View {
    let agentId: String
    let messages: [ParsedMessage]
    let tools: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("agent-\(agentId)")
                        .font(DS.Typography.captionMono)
                        .foregroundStyle(DS.Color.Text.secondary)
                    Text("\(messages.count) messages")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.tertiary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.Color.Text.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Space.lg)

            Divider().overlay(DS.Color.Border.subtle)

            // Full message list — this is the only ScrollView, inside a dedicated sheet
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.sm) {
                    if !tools.isEmpty {
                        toolsSummarySheet(tools: tools)
                    }

                    ForEach(messages) { msg in
                        MessageRowView(message: msg)
                    }
                }
                .padding(DS.Space.lg)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(DS.Color.Surface.base)
    }

    private func toolsSummarySheet(tools: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Tools used")
                .font(DS.Typography.micro)
                .foregroundStyle(DS.Color.Text.quaternary)

            FlowLayout(spacing: DS.Space.xs) {
                ForEach(tools, id: \.self) { tool in
                    Text(tool)
                        .font(DS.Typography.microMono)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(DS.Color.Surface.elevated)
                        )
                }
            }
        }
        .padding(.bottom, DS.Space.sm)
    }
}
