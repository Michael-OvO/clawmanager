import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area (also serves as drag region for hidden title bar)
            // Logo is centered via overlay so the traffic light spacer doesn't shift it
            Color.clear
                .frame(height: 52)
                .overlay {
                    HStack(spacing: DS.Space.xs) {
                        // Claw icon
                        Canvas { context, size in
                            let cx = size.width / 2
                            let cy = size.height / 2
                            let slant: CGFloat = 1.5
                            let halfH: CGFloat = 6
                            let spacing: CGFloat = 4

                            for i in -1...1 {
                                let dx = CGFloat(i) * spacing
                                var path = Path()
                                path.move(to: CGPoint(x: cx + dx + slant, y: cy - halfH))
                                path.addLine(to: CGPoint(x: cx + dx - slant, y: cy + halfH))

                                context.stroke(
                                    path,
                                    with: .color(DS.Color.Accent.primary),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                )
                            }
                        }
                        .frame(width: 16, height: 14)
                        .shadow(color: DS.Color.Accent.primary.opacity(0.35), radius: 3)

                        Text("ClawManager")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Color.Text.secondary)
                    }
                }

            // Search bar
            searchBar
                .padding(.horizontal, DS.Space.md)
                .padding(.bottom, DS.Space.md)

            // Status filter chips
            statusFilters
                .padding(.horizontal, DS.Space.md)
                .padding(.bottom, DS.Space.md)

            Divider()
                .overlay(DS.Color.Border.subtle)

            // Projects list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("PROJECTS")
                        .font(DS.Typography.micro)
                        .tracking(0.8)
                        .foregroundStyle(DS.Color.Text.quaternary)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.top, DS.Space.lg)
                        .padding(.bottom, DS.Space.xs)

                    ForEach(store.projects) { project in
                        ProjectRow(
                            project: project,
                            isSelected: uiState.selectedProject == project.workspacePath
                        )
                        .onTapGesture {
                            withAnimation(DS.Motion.springInteractive) {
                                if uiState.selectedProject == project.workspacePath {
                                    uiState.selectedProject = nil
                                } else {
                                    uiState.selectedProject = project.workspacePath
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.md)
            }
        }
        .background(DS.Color.Surface.raised)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(DS.Color.Text.tertiary)

            TextField("Search sessions...", text: Bindable(uiState).searchQuery)
                .textFieldStyle(.plain)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.Text.primary)
                .focused($isSearchFocused)

            if !uiState.searchQuery.isEmpty {
                Button {
                    uiState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.Text.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(DS.Typography.microMono)
                    .foregroundStyle(DS.Color.Text.quaternary)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.md - 4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.Surface.overlay)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(
                            isSearchFocused ? DS.Color.Border.strong : DS.Color.Border.subtle,
                            lineWidth: 1
                        )
                )
        )
        .if(isSearchFocused) { view in
            view.shadow(color: DS.Color.Accent.primary.opacity(0.08), radius: 6)
        }
    }

    // MARK: - Status Filters

    /// Single-pass count by status (replaces 5x separate .filter calls).
    private var statusCounts: [SessionStatus: Int] {
        Dictionary(grouping: store.sessions, by: \.status).mapValues(\.count)
    }

    private var statusFilters: some View {
        FlowLayout(spacing: DS.Space.xs) {
            StatusFilterChip(
                label: "All",
                count: store.sessions.count,
                isSelected: uiState.statusFilter == .all,
                dotColor: nil
            ) {
                withAnimation(DS.Motion.springInteractive) {
                    uiState.statusFilter = .all
                }
            }

            let counts = statusCounts
            ForEach(SessionStatus.allCases) { status in
                StatusFilterChip(
                    label: status.label,
                    count: counts[status] ?? 0,
                    isSelected: uiState.statusFilter == .specific(status),
                    dotColor: status.dotColor
                ) {
                    withAnimation(DS.Motion.springInteractive) {
                        uiState.statusFilter = .specific(status)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalSize.width = max(totalSize.width, currentX - spacing)
        }

        totalSize.height = currentY + lineHeight
        return LayoutResult(positions: positions, size: totalSize)
    }
}
