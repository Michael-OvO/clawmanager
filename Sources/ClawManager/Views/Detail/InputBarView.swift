import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(DS.Color.Border.subtle)

            HStack(spacing: DS.Space.sm) {
                TextField("Send a message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.Text.primary)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            send()
                        }
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend ? DS.Color.Accent.primary : DS.Color.Text.quaternary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.md)
        }
        .background(DS.Color.Surface.raised)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}
