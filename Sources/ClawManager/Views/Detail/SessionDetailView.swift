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

                    // Message feed (with live messages when interactive)
                    MessageFeedView(
                        messages: detail.messages,
                        liveMessages: isThisSessionInteractive ? store.liveMessages : [],
                        streamingMessage: isThisSessionInteractive ? store.currentStreamingMessage : nil
                    )
                    .layoutPriority(1)

                    // Tool approval bar (interactive) or pending interaction bar (read-only)
                    if let toolCall = store.pendingToolApproval, isThisSessionInteractive {
                        ToolApprovalBar(
                            toolCall: toolCall,
                            onApprove: { store.approveToolCall() },
                            onReject: { store.rejectToolCall() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let pending = detail.summary.pendingInteraction, !isThisSessionInteractive {
                        PendingInteractionBar(interaction: pending)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Input bar (when connected)
                    if isThisSessionInteractive && store.connectionState.isActive {
                        InputBarView { text in
                            store.sendInteractiveMessage(text)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DS.Motion.springSmooth, value: store.pendingToolApproval != nil)
                .animation(DS.Motion.springSmooth, value: isThisSessionInteractive)
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
