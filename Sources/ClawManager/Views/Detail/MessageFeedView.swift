import SwiftUI

struct MessageFeedView: View {
    let messages: [ParsedMessage]
    var liveMessages: [LiveMessage] = []
    var streamingMessage: LiveMessage?

    /// Throttle: only allow one scrollToBottom per interval.
    @State private var scrollThrottleTask: Task<Void, Never>?
    @State private var needsScroll = false

    private var visibleMessages: [ParsedMessage] {
        messages.filter { $0.type == .user || $0.type == .assistant }
    }

    private var hasAnyContent: Bool {
        !visibleMessages.isEmpty || !liveMessages.isEmpty || streamingMessage != nil
    }

    /// Lightweight check: did the streaming content grow? Uses count instead of full string equality.
    private var streamingLength: Int {
        streamingMessage?.textAccumulator.count ?? -1
    }

    var body: some View {
        if !hasAnyContent {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No messages yet",
                description: "Messages will appear here as the session progresses"
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.md) {
                        // Historical messages
                        ForEach(visibleMessages) { msg in
                            MessageRowView(message: msg)
                                .id(msg.id)
                        }

                        // Completed live messages
                        ForEach(liveMessages) { msg in
                            LiveMessageRowView(message: msg)
                                .id("live-\(msg.id)")
                        }

                        // Currently streaming message
                        if let streaming = streamingMessage {
                            LiveMessageRowView(message: streaming)
                                .id("streaming")
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.lg)
                }
                .onChange(of: visibleMessages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: liveMessages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: streamingLength) { _, _ in
                    throttledScrollToBottom(proxy)
                }
            }
        }
    }

    /// Immediate scroll for discrete events (new message added).
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let targetId = scrollTargetId
        guard let targetId else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
    }

    /// Throttled scroll for high-frequency events (streaming tokens).
    /// Fires at most once every 200ms to prevent animation stacking.
    private func throttledScrollToBottom(_ proxy: ScrollViewProxy) {
        needsScroll = true
        guard scrollThrottleTask == nil else { return }
        scrollThrottleTask = Task { @MainActor in
            while needsScroll {
                needsScroll = false
                scrollToBottom(proxy)
                try? await Task.sleep(for: .milliseconds(200))
            }
            scrollThrottleTask = nil
        }
    }

    private var scrollTargetId: AnyHashable? {
        if streamingMessage != nil {
            return "streaming"
        } else if let lastLive = liveMessages.last {
            return "live-\(lastLive.id)"
        } else if let lastHistorical = visibleMessages.last {
            return lastHistorical.id
        }
        return nil
    }
}
