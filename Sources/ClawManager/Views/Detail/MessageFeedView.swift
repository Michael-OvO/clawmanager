import SwiftUI

struct MessageFeedView: View {
    let messages: [ParsedMessage]
    var isStreaming: Bool = false
    var streamingText: String = ""
    var streamingThinking: String = ""

    /// Whether the user is scrolled near the bottom. Auto-scroll only fires
    /// when this is true, so users can freely scroll up without being snapped back.
    @State private var isNearBottom = true
    /// Debounced version of isNearBottom — only updates after the value
    /// stabilizes for 150ms. Prevents the scroll button from flickering
    /// when the scroll position oscillates around the 80px threshold.
    @State private var showScrollButton = false
    @State private var scrollButtonDebounce: Task<Void, Never>?
    @State private var isHoveringButton = false

    /// Cached filter result — only recomputed when message count changes.
    @State private var cachedVisible: [ParsedMessage] = []

    /// Throttle token: prevents stacking scroll animations on every character.
    @State private var scrollThrottleTask: Task<Void, Never>?

    var body: some View {
        if cachedVisible.isEmpty && !isStreaming {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No messages yet",
                description: "Messages will appear here as the session progresses"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { refilter() }
            .onChange(of: messages.count) { _, _ in refilter() }
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DS.Space.md) {
                            ForEach(cachedVisible) { msg in
                                MessageRowView(message: msg)
                                    .id(msg.id)
                            }

                            // Live streaming indicator at the bottom
                            if isStreaming {
                                ThinkingIndicatorView(
                                    streamingText: streamingText,
                                    streamingThinking: streamingThinking
                                )
                                .id("streaming-indicator")
                            }
                        }
                        .padding(.horizontal, DS.Space.xl)
                        .padding(.vertical, DS.Space.lg)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let distanceFromBottom = geometry.contentSize.height
                            - geometry.contentOffset.y
                            - geometry.containerSize.height
                        return distanceFromBottom < 80
                    } action: { _, isAtBottom in
                        isNearBottom = isAtBottom
                        // Debounce the button visibility to prevent rapid
                        // show/hide cycles when scroll oscillates near threshold.
                        scrollButtonDebounce?.cancel()
                        let shouldShow = !isAtBottom
                        if shouldShow == showScrollButton { return }
                        if !shouldShow {
                            // Hide immediately when reaching bottom
                            withAnimation(.easeOut(duration: 0.15)) {
                                showScrollButton = false
                            }
                        } else {
                            // Show after a short delay to avoid flicker
                            scrollButtonDebounce = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showScrollButton = true
                                }
                            }
                        }
                    }
                    .onAppear { refilter() }
                    .onChange(of: messages.count) { _, _ in
                        refilter()
                        if isNearBottom {
                            scrollToBottom(proxy)
                        }
                    }
                    .onChange(of: streamingText.count) { _, _ in
                        throttledScroll(proxy)
                    }
                    .onChange(of: streamingThinking.count) { _, _ in
                        throttledScroll(proxy)
                    }
                    .onChange(of: isStreaming) { _, streaming in
                        if streaming {
                            scrollToBottom(proxy, anchor: .bottom)
                        }
                    }

                    // Scroll-to-bottom button — appears when user has scrolled up.
                    // Uses debounced `showScrollButton` to avoid flicker at the threshold.
                    if showScrollButton {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showScrollButton = false
                            }
                            scrollToBottom(proxy, anchor: .bottom)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DS.Color.Text.secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(DS.Color.Surface.overlay)
                                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(DS.Color.Border.default, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, DS.Space.lg)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func refilter() {
        cachedVisible = messages.filter { $0.type == .user || $0.type == .assistant }
    }

    /// Coalesce rapid streaming scroll calls into one scroll every ~150ms.
    /// Prevents stacking dozens of 0.2s animations per second.
    private func throttledScroll(_ proxy: ScrollViewProxy) {
        guard isStreaming && isNearBottom else { return }
        guard scrollThrottleTask == nil else { return }

        scrollThrottleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            scrollToBottom(proxy, anchor: .bottom)
            scrollThrottleTask = nil
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, anchor: UnitPoint = .bottom) {
        let targetId: AnyHashable = isStreaming
            ? "streaming-indicator"
            : (cachedVisible.last?.id ?? "" as AnyHashable)
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(targetId, anchor: anchor)
        }
    }
}
