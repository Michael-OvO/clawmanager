import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Runs when @NSApplicationDelegateAdaptor creates us (during App.init()),
    // BEFORE NSApplication.run() reads saved state — the only reliable
    // point to delete saved window state before macOS tries to restore it.
    override init() {
        super.init()
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        Self.clearSavedWindowState()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // SwiftPM builds a bare executable (no .app bundle), so macOS
        // defaults to accessory/background mode. Force regular app mode
        // to get a menu bar, Dock icon, and Cmd+Tab presence.
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI window creation can race with this callback — especially
        // under Xcode's launch pipeline. Run cleanup on the next tick, then
        // again after a short delay as a safety net for late-arriving windows.
        DispatchQueue.main.async { [self] in
            self.closeExtraWindowsAndStyle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            self.closeExtraWindowsAndStyle()
        }

        // Bring the app to front on launch
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Delete saved state right before quitting so nothing persists
        // for the next launch (covers normal quit; Xcode SIGKILL is
        // handled by the init() cleanup on the next launch).
        Self.clearSavedWindowState()
    }

    @MainActor private func closeExtraWindowsAndStyle() {
        let windows = NSApplication.shared.windows
        // Close any extra windows left over from state restoration.
        if windows.count > 1 {
            for window in windows.dropFirst() {
                window.close()
            }
        }

        // Mark ALL remaining windows non-restorable so macOS won't
        // save their state when the app quits.
        for window in NSApplication.shared.windows {
            window.isRestorable = false
        }

        // Style the primary window.
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 880, height: 600)
            window.backgroundColor = NSColor(red: 0.047, green: 0.047, blue: 0.055, alpha: 1.0)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When clicking the Dock icon, just bring existing window to front
        // instead of allowing the system to create a new one.
        if flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private static func clearSavedWindowState() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let path = NSHomeDirectory()
                + "/Library/Saved Application State/\(bundleID).savedState"
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
