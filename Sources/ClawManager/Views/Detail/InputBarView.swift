import SwiftUI
import AppKit

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
                NativeTextField(
                    text: $text,
                    placeholder: "Message Claude...",
                    onSubmit: send
                )
                .frame(minHeight: 22)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            canSend ? DS.Color.Accent.primary : DS.Color.Text.quaternary
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
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

// MARK: - Native NSTextField Wrapper

/// Wraps NSTextField for reliable first-responder handling on macOS.
/// SwiftUI's @FocusState doesn't reliably grant focus in complex view
/// hierarchies (NavigationSplitView, animations, conditional rendering).
/// NSTextField.becomeFirstResponder() is the native API that always works.
private struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = NSColor(DS.Color.Text.primary)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(DS.Color.Text.quaternary),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.maximumNumberOfLines = 6
        field.cell?.wraps = true
        field.cell?.isScrollable = true
        field.cell?.lineBreakMode = .byWordWrapping
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }

        // Acquire first responder once the field is in a window
        if context.coordinator.needsFocus, let window = field.window {
            context.coordinator.needsFocus = false
            // Async to let the view settle into the window hierarchy first
            DispatchQueue.main.async {
                window.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        var needsFocus = true

        init(_ parent: NativeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Handle Enter key → submit, and allow other key commands to pass through.
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true // consumed
            }
            return false // let default handling proceed
        }
    }
}
