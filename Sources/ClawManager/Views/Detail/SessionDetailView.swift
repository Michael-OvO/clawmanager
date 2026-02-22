import SwiftUI

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState

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

                    // Message feed — grows automatically as the tail service
                    // appends new ParsedMessage objects from the JSONL file
                    MessageFeedView(messages: detail.messages)
                        .frame(maxHeight: .infinity)

                    // Read-only pending interaction indicator
                    if let pending = detail.summary.pendingInteraction {
                        PendingInteractionBar(interaction: pending)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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

// MARK: - Read-Only Pending Interaction Bar
//
// Shows when a session is waiting for tool approval or a user question,
// but as an informational display only — the user approves in their
// actual Claude Code session (terminal or VSCode), not here.

private struct PendingInteractionBar: View {
    let interaction: PendingInteraction
    @State private var borderPulse = false

    private var icon: String {
        interaction.type == .question ? "questionmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var label: String {
        if interaction.type == .question {
            return "Waiting for your answer"
        }
        return "Waiting for approval: \(interaction.toolName ?? "tool")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Color.Status.waitingDot.opacity(borderPulse ? 0.6 : 0.3))
                .frame(height: 2)

            HStack(spacing: DS.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Color.Status.waitingDot)

                Text(label)
                    .font(DS.Typography.small)
                    .foregroundStyle(DS.Color.Text.secondary)

                Spacer()

                Text("Respond in Claude Code")
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Color.Text.quaternary)
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
}
