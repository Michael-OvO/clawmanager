import SwiftUI

@main
struct ClawManagerApp: App {
    @State private var sessionStore = SessionStore()
    @State private var uiState = UIState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ZStack {
                if uiState.showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            uiState.showSplash = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .environment(sessionStore)
            .environment(uiState)
            .onAppear {
                sessionStore.startMonitoring()
            }
            .preferredColorScheme(.dark)
            .frame(minWidth: 880, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Session") {
                Button("Quick Open") {
                    uiState.toggleCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Refresh Sessions") {
                    Task {
                        await sessionStore.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Clear Filters") {
                    uiState.clearFilters()
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }
}
