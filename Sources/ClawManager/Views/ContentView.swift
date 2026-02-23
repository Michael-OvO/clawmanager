import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var uiState
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } content: {
                SessionListView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
            } detail: {
                SessionDetailView()
            }
            .navigationSplitViewStyle(.balanced)
            // Hide the system toolbar background so the window's
            // DS.Color.Surface.base shows through the title bar area.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(.hidden, for: .windowToolbar)

            // Command palette overlay
            if uiState.isCommandPaletteOpen {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(DS.Color.Surface.base)
    }
}
