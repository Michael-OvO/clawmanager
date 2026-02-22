import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // SwiftPM builds a bare executable (no .app bundle), so macOS
        // defaults to accessory/background mode. Force regular app mode
        // to get a menu bar, Dock icon, and Cmd+Tab presence.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            // Transparent title bar with content extending underneath —
            // keeps standard macOS window management (Mission Control,
            // Cmd+Tab, window ordering) while looking custom.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 880, height: 600)
            window.backgroundColor = NSColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1.0)
        }

        // Bring the app to front on launch
        NSApp.activate()
    }
}
