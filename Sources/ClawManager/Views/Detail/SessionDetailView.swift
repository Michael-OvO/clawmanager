import SwiftUI

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState

    private var isThisSessionInteractive: Bool {
        guard let detail = store.selectedDetail else { return false }
        return store.interactiveSessionId == detail.summary.sessionId
    }

    var body: some View {
        Group {
            if let detail = store.selectedDetail {
                VStack(spacing: 0) {
                    DetailHeaderView(
                        summary: detail.summary,
                        connectionState: isThisSessionInteractive ? store.connectionState : .disconnected,
                        isInteractive: isThisSessionInteractive,
                        onConnect: {
                            store.connectToSession(detail.summary.sessionId)
                        },
                        onDisconnect: {
                            store.disconnectFromSession()
                        }
                    )

                    Divider()
                        .overlay(DS.Color.Border.subtle)

                    // Subagent panel (above message feed when subagents exist)
                    if !detail.subagents.isEmpty {
                        SubagentPanelView(subagents: detail.subagents)

                        Divider()
                            .overlay(DS.Color.Border.subtle)
                    }

                    // Message feed — reads live/streaming data directly from @Observable store
                    MessageFeedView(
                        messages: detail.messages,
                        isInteractive: isThisSessionInteractive
                    )
                    .layoutPriority(1)

                    // Tool approval bar — unified for both interactive and read-only sessions
                    if let toolCall = store.pendingToolApproval, isThisSessionInteractive {
                        // Interactive: approve/reject directly via the live stdin pipe
                        ToolApprovalBar(
                            toolCall: toolCall,
                            onApprove: { store.approveToolCall() },
                            onReject: { store.rejectToolCall() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let pending = detail.summary.pendingInteraction, !isThisSessionInteractive {
                        // Read-only: connect to the session and auto-approve/reject
                        ToolApprovalBar(
                            interaction: pending,
                            onApprove: { store.connectAndApprove(detail.summary.sessionId) },
                            onReject: { store.connectAndReject(detail.summary.sessionId) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Input bar (when connected)
                    if isThisSessionInteractive && store.connectionState.isActive {
                        InputBarView { text in
                            store.sendInteractiveMessage(text)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    icon: "sidebar.squares.right",
                    title: "Select a session",
                    description: "Choose a session from the list to view its details"
                )
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
