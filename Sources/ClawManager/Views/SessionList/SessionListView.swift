import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState

    private var filteredSessions: [SessionSummary] {
        uiState.filteredSessions(from: store.sessions)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.sm)

            Divider()
                .overlay(DS.Color.Border.subtle)

            // Session list
            if store.isLoading {
                Spacer()
                LoadingDotsView()
                Spacer()
            } else if filteredSessions.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No sessions found",
                    description: "Try adjusting your search or filters",
                    actionLabel: uiState.statusFilter != .all || !uiState.searchQuery.isEmpty ? "Clear filters" : nil,
                    action: { uiState.clearFilters() }
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        ForEach(filteredSessions) { session in
                            SessionRowView(
                                session: session,
                                isSelected: uiState.selectedSessionId == session.sessionId
                            )
                            .onTapGesture {
                                withAnimation(DS.Motion.springSmooth) {
                                    uiState.selectSession(session.sessionId)
                                }
                                Task {
                                    await store.loadDetail(for: session.sessionId)
                                }
                            }
                        }
                    }
                    .padding(DS.Space.md)
                }
            }
        }
        .background(DS.Color.Surface.base)
    }

    private var header: some View {
        HStack {
            Text("Sessions")
                .font(DS.Typography.subheading)
                .foregroundStyle(DS.Color.Text.secondary)

            Text("\(filteredSessions.count)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.Text.tertiary)

            Spacer()

            // Sort picker
            Menu {
                ForEach(UIState.SortBy.allCases, id: \.self) { sort in
                    Button {
                        uiState.sortBy = sort
                    } label: {
                        HStack {
                            Text(sort.rawValue)
                            if uiState.sortBy == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                    Text(uiState.sortBy.rawValue)
                        .font(DS.Typography.micro)
                }
                .foregroundStyle(DS.Color.Text.tertiary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xs)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.Surface.overlay)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.Border.subtle, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}
