import SwiftUI

/// Live streaming indicator shown while Claude is actively processing.
///
/// Displays two distinct phases:
/// 1. **Thinking phase** — extended thinking tokens stream into a collapsible section
/// 2. **Response phase** — visible response text streams in below
///
/// The thinking section auto-collapses once response text begins,
/// keeping the user focused on the answer while still accessible.
struct ThinkingIndicatorView: View {
    let streamingText: String
    let streamingThinking: String

    @State private var animating = false
    @State private var thinkingExpanded = true

    private var hasResponseText: Bool { !streamingText.isEmpty }
    private var hasThinking: Bool { !streamingThinking.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if hasThinking {
                thinkingSection
            }

            if hasResponseText {
                responseSection
            }

            if !hasThinking && !hasResponseText {
                waitingIndicator
            }
        }
        .onChange(of: hasResponseText) { _, hasResponse in
            if hasResponse && thinkingExpanded {
                withAnimation(DS.Motion.normal) {
                    thinkingExpanded = false
                }
            }
        }
        .onAppear { animating = true }
    }

    // MARK: - Thinking Section

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DS.Motion.springSmooth) {
                    thinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Color.Status.idleDot)
                        .symbolEffect(.pulse, isActive: !hasResponseText)

                    Text("Thinking")
                        .font(DS.Typography.small)
                        .foregroundStyle(DS.Color.Status.idleDot)

                    if !hasResponseText {
                        pulseDots
                    }

                    Spacer()

                    // Use utf8.count (O(1) on contiguous strings) instead of .count (O(N) grapheme clusters)
                    Text("\(streamingThinking.utf8.count) chars")
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Color.Text.quaternary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .rotationEffect(.degrees(thinkingExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.sm + 2)
                .padding(.vertical, DS.Space.xs + 2)
            }
            .buttonStyle(.plain)

            if thinkingExpanded {
                Divider()
                    .overlay(DS.Color.Status.idleDot.opacity(0.15))
                    .padding(.horizontal, DS.Space.sm)

                // Show only the tail of thinking text to avoid laying out
                // thousands of characters on every streaming token.
                ScrollView {
                    Text(thinkingTail)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.sm)
                }
                .frame(maxHeight: 150)
                .defaultScrollAnchor(.bottom)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.Status.idleDot.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.Status.idleDot.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Response Section

    private var responseSection: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(DS.Color.Accent.secondary)
                .frame(width: 2)
                .opacity(animating ? 1.0 : 0.3)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: animating
                )

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Claude")
                    .font(DS.Typography.small)
                    .foregroundStyle(DS.Color.Accent.secondary)

                // Show only the tail of response text during streaming to avoid
                // full Text layout of the entire accumulated response on every token.
                Text(responseTail)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.Text.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Waiting Indicator

    private var waitingIndicator: some View {
        HStack(spacing: DS.Space.sm) {
            pulseDots

            Text("Thinking...")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.Text.tertiary)
                .italic()

            Spacer()
        }
    }

    // MARK: - Pulse Dots

    private var pulseDots: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.Color.Status.idleDot)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1.0 : 0.4)
                    .opacity(animating ? 1.0 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
    }

    // MARK: - Truncated Tails

    /// Last ~800 characters of thinking text — avoids laying out a 50K+ string.
    private var thinkingTail: String {
        if streamingThinking.count <= 800 { return streamingThinking }
        return "..." + streamingThinking.suffix(800)
    }

    /// Last ~2000 characters of response text for the streaming preview.
    private var responseTail: String {
        if streamingText.count <= 2000 { return streamingText }
        return "..." + streamingText.suffix(2000)
    }
}
