import SwiftUI
@preconcurrency import AppKit

// MARK: - Input Bar

struct InputBarView: View {
    let onSend: (String) -> Void

    @State private var text = ""

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(DS.Color.Border.subtle)

            HStack(alignment: .bottom, spacing: DS.Space.sm) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Message Claude...")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.Text.quaternary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }

                    InputTextView(
                        text: $text,
                        onSubmit: send
                    )
                }
                .frame(minHeight: 24, maxHeight: 120)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            canSend ? DS.Color.Accent.primary : DS.Color.Text.quaternary
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(DS.Color.Surface.raised)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

// MARK: - NSTextView with local event monitor
//
// SwiftUI's hosting view inside NavigationSplitView intercepts keyDown: events
// during performKeyEquivalent: traversal, preventing regular typing from reaching
// embedded NSViews. The local event monitor intercepts key events BEFORE SwiftUI's
// dispatch chain, routing them directly to our NSTextView.

private struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(DS.Color.Text.primary)
        textView.insertionPointColor = NSColor(DS.Color.Accent.primary)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]

        // Store references for the event monitor (we're on MainActor here)
        context.coordinator.textView = textView
        context.coordinator.submitAction = onSubmit
        context.coordinator.installEventMonitor()

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != text {
            textView.string = text
        }

        // Grab focus once we're in a window
        if !context.coordinator.hasFocused, let window = textView.window {
            context.coordinator.hasFocused = true
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        var hasFocused = false
        // nonisolated(unsafe) allows the event monitor closure (which is
        // nonisolated) to access these without crossing actor boundaries.
        // Safe because the local event monitor always fires on the main thread.
        nonisolated(unsafe) weak var textView: NSTextView?
        nonisolated(unsafe) var submitAction: (() -> Void)?
        private var eventMonitor: Any?

        init(_ parent: InputTextView) {
            self.parent = parent
        }

        deinit {
            removeEventMonitor()
        }

        // MARK: - Local Event Monitor

        func installEventMonitor() {
            removeEventMonitor()
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Access nonisolated(unsafe) refs — safe, we're on main thread
                guard let textView = self.textView else { return event }

                // NSEvent's Sendable conformance is explicitly unavailable, so we
                // wrap it going IN and return a simple Sendable enum coming OUT.
                // The submit closure also can't cross, so we signal it and call outside.
                let safeEvent = UncheckedSendableEvent(event)

                let action: KeyAction = MainActor.assumeIsolated {
                    let event = safeEvent.event

                    guard textView.window?.firstResponder === textView else {
                        return .passthrough
                    }

                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    // Command-key combos (Cmd+C, Cmd+V, Cmd+K, etc.) → pass through
                    if flags.contains(.command) { return .passthrough }

                    // Escape → pass through to SwiftUI
                    if event.keyCode == 53 { return .passthrough }

                    // Return key
                    if event.keyCode == 36 {
                        if flags.contains(.shift) {
                            textView.insertNewlineIgnoringFieldEditor(nil)
                        }
                        return flags.contains(.shift) ? .consumed : .submit
                    }

                    // All other keys → route directly to text input system
                    textView.interpretKeyEvents([event])
                    return .consumed
                }

                switch action {
                case .passthrough: return event
                case .consumed:    return nil
                case .submit:      self.submitAction?(); return nil
                }
            }
        }

        /// Wrapper to let NSEvent cross into MainActor.assumeIsolated.
        /// Safe because local event monitors always fire on the main thread.
        private struct UncheckedSendableEvent: @unchecked Sendable {
            let event: NSEvent
            init(_ event: NSEvent) { self.event = event }
        }

        private enum KeyAction: Sendable {
            case passthrough  // let the event continue to SwiftUI
            case consumed     // we handled it (typing, shift+return)
            case submit       // return key → call submit outside MainActor
        }

        func removeEventMonitor() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        // Fallback for normal keyDown: delivery (belt-and-suspenders)
        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
