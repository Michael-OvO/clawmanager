import Foundation
import Observation

@Observable
final class UIState {
    // Selection
    var selectedSessionId: String?

    // Filters
    var statusFilter: StatusFilter = .all
    var searchQuery: String = ""
    var sortBy: SortBy = .recent
    var selectedProject: String?

    // Command palette
    var isCommandPaletteOpen = false

    // Splash
    var showSplash = true

    // MARK: - Types

    enum StatusFilter: Hashable {
        case all
        case specific(SessionStatus)
    }

    enum SortBy: String, CaseIterable {
        case recent = "Recent"
        case name = "Name"
        case status = "Status"
    }

    // MARK: - Actions

    func selectSession(_ id: String?) {
        selectedSessionId = id
    }

    func toggleCommandPalette() {
        isCommandPaletteOpen.toggle()
    }

    func clearFilters() {
        statusFilter = .all
        searchQuery = ""
        selectedProject = nil
    }

    /// Filter and sort sessions based on current UI state.
    func filteredSessions(from sessions: [SessionSummary]) -> [SessionSummary] {
        var result = sessions

        // Status filter
        if case .specific(let status) = statusFilter {
            result = result.filter { $0.status == status }
        }

        // Project filter
        if let project = selectedProject {
            result = result.filter { $0.workspacePath == project }
        }

        // Search filter
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.projectName.lowercased().contains(q) ||
                $0.sessionId.lowercased().contains(q) ||
                $0.workspacePath.lowercased().contains(q) ||
                ($0.gitBranch?.lowercased().contains(q) ?? false)
            }
        }

        // Sort — all branches use sessionId as a stable tiebreaker
        switch sortBy {
        case .recent:
            result.sort {
                if $0.lastActivity != $1.lastActivity {
                    return $0.lastActivity > $1.lastActivity
                }
                return $0.sessionId < $1.sessionId
            }
        case .name:
            result.sort {
                let cmp = $0.projectName.localizedCaseInsensitiveCompare($1.projectName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.sessionId < $1.sessionId
            }
        case .status:
            result.sort {
                if $0.status.sortOrder != $1.status.sortOrder {
                    return $0.status.sortOrder < $1.status.sortOrder
                }
                return $0.sessionId < $1.sessionId
            }
        }

        return result
    }
}
