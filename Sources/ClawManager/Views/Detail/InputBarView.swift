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

        context.coordinator.textView = textView
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
            submitAction = parent.onSubmit
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let textView = self.textView,
                      textView.window?.firstResponder === textView else {
                    return event // not our text view — pass through
                }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Command-key combos (Cmd+C, Cmd+V, Cmd+K, etc.) → pass through
                if flags.contains(.command) {
                    return event
                }

                // Escape → pass through to SwiftUI
                if event.keyCode == 53 {
                    return event
                }

                // Return key
                if event.keyCode == 36 {
                    if flags.contains(.shift) {
                        textView.insertNewlineIgnoringFieldEditor(nil)
                    } else {
                        self.submitAction?()
                    }
                    return nil // consumed
                }

                // All other keys → route directly to text input system
                textView.interpretKeyEvents([event])
                return nil // consumed
            }
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
