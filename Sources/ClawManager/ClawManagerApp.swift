import SwiftUI

@main
struct ClawManagerApp: App {
    @State private var sessionStore = SessionStore()
    @State private var uiState = UIState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("ClawManager", id: "main") {
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
                Diag.log(.info, .app, "App launched")
                sessionStore.startMonitoring()
            }
            .preferredColorScheme(.dark)
            .frame(minWidth: 880, minHeight: 600)
        }
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

            CommandMenu("Debug") {
                Button("Dump State Now") {
                    Task { await sessionStore.dumpState() }
                    Diag.log(.info, .state, "Manual state dump triggered")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Clear Diagnostic Log") {
                    try? FileManager.default.removeItem(atPath: Diag.logPath)
                    Diag.log(.info, .app, "Diagnostic log cleared")
                }

                Divider()

                Button("Reveal Log in Finder") {
                    NSWorkspace.shared.selectFile(Diag.logPath, inFileViewerRootedAtPath: "/tmp")
                }

                Button("Reveal State in Finder") {
                    NSWorkspace.shared.selectFile(Diag.statePath, inFileViewerRootedAtPath: "/tmp")
                }
            }
        }
    }
}
