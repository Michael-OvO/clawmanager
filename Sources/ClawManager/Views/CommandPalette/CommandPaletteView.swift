import SwiftUI

struct CommandPaletteView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [SessionSummary] {
        let sessions = store.sessions
        guard !query.isEmpty else { return Array(sessions.prefix(10)) }
        let q = query.lowercased()
        return sessions.filter {
            $0.projectName.lowercased().contains(q) ||
            $0.sessionId.lowercased().contains(q) ||
            $0.workspacePath.lowercased().contains(q) ||
            ($0.gitBranch?.lowercased().contains(q) ?? false)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Palette
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.Text.tertiary)

                    TextField("Search sessions...", text: $query)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.heading)
                        .foregroundStyle(DS.Color.Text.primary)
                        .focused($isSearchFocused)

                    keyCapLabel("esc")
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(height: 48)

                Divider()
                    .overlay(DS.Color.Border.subtle)

                // Results
                if filtered.isEmpty {
                    VStack(spacing: DS.Space.sm) {
                        Text("No matching sessions")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.Text.tertiary)
                    }
                    .frame(height: 80)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DS.Space.xxs) {
                            Text("SESSIONS")
                                .font(DS.Typography.micro)
                                .tracking(0.8)
                                .foregroundStyle(DS.Color.Text.quaternary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Space.md)
                                .padding(.top, DS.Space.sm)
                                .padding(.bottom, DS.Space.xs)

                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, session in
                                resultRow(session: session, index: index)
                            }
                        }
                        .padding(.vertical, DS.Space.xs)
                    }
                    .frame(maxHeight: 340)
                }
            }
            .frame(width: 560)
            .background(DS.Color.Surface.floating)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xxl)
                    .stroke(DS.Color.Border.default, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
            .offset(y: -60)
        }
        .onAppear { isSearchFocused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, filtered.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if let session = filtered[safe: selectedIndex] {
                selectSession(session)
            }
            return .handled
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    // MARK: - Result Row

    private func resultRow(session: SessionSummary, index: Int) -> some View {
        Button { selectSession(session) } label: {
            HStack(spacing: DS.Space.md) {
                // Focus indicator bar
                if index == selectedIndex {
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .fill(DS.Color.Accent.primary)
                        .frame(width: 2, height: 16)
                        .transition(.scale(scale: 0, anchor: .leading))
                }

                Circle()
                    .fill(session.status.dotColor)
                    .frame(width: 6, height: 6)

                Text(session.projectName)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.Text.primary)
                    .lineLimit(1)

                if let branch = session.gitBranch {
                    Text(branch)
                        .font(DS.Typography.captionMono)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(Formatters.shortId(session.sessionId))
                    .font(DS.Typography.microMono)
                    .foregroundStyle(DS.Color.Text.quaternary)

                Text(Formatters.timeAgo(session.lastActivity))
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Color.Text.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(index == selectedIndex ? DS.Color.Surface.elevated : .clear)
            )
            .padding(.horizontal, DS.Space.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func keyCapLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.micro)
            .foregroundStyle(DS.Color.Text.quaternary)
            .padding(.horizontal, DS.Space.md - 4)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Color.Surface.overlay)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.xs)
                            .stroke(DS.Color.Border.subtle, lineWidth: 1)
                    )
            )
    }

    private func dismiss() {
        uiState.isCommandPaletteOpen = false
    }

    private func selectSession(_ session: SessionSummary) {
        uiState.selectSession(session.sessionId)
        dismiss()
    }
}
