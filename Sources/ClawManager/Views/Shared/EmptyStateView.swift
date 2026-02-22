import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(DS.Color.Text.quaternary)

            Text(title)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.Color.Text.tertiary)

            Text(description)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.Text.quaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.Accent.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Space.xs)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1.0 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.2)) {
                appeared = true
            }
        }
    }
}

// MARK: - Loading Dots

struct LoadingDotsView: View {
    @State private var animating = false

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md - 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DS.Color.Text.quaternary)
                        .frame(width: 6, height: 6)
                        .offset(y: animating ? -6 : 0)
                        .animation(
                            .spring(duration: 0.4, bounce: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                            value: animating
                        )
                }
            }

            Text("Discovering sessions...")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.Text.tertiary)
        }
        .onAppear { animating = true }
    }
}
