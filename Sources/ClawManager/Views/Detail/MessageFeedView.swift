import SwiftUI

struct MessageFeedView: View {
    let messages: [ParsedMessage]

    private var visibleMessages: [ParsedMessage] {
        messages.filter { $0.type == .user || $0.type == .assistant }
    }

    var body: some View {
        if visibleMessages.isEmpty {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No messages yet",
                description: "Messages will appear here as the session progresses"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.md) {
                        ForEach(visibleMessages) { msg in
                            MessageRowView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.lg)
                }
                .onChange(of: visibleMessages.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = visibleMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
