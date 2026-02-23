import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // SwiftPM builds a bare executable (no .app bundle), so macOS
        // defaults to accessory/background mode. Force regular app mode
        // to get a menu bar, Dock icon, and Cmd+Tab presence.
        NSApp.setActivationPolicy(.regular)

        // Explicitly disable state restoration. Using removeObject merely
        // deletes the preference, falling back to the system default (which
        // restores windows). Setting it to false ensures no restoration.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI window creation can race with this callback, so schedule
        // the extra-window cleanup for the next run-loop tick.
        DispatchQueue.main.async { [self] in
            self.closeExtraWindowsAndStyle()
        }

        // Bring the app to front on launch
        NSApp.activate()
    }

    @MainActor private func closeExtraWindowsAndStyle() {
        let windows = NSApplication.shared.windows
        // Close any extra windows left over from state restoration.
        if windows.count > 1 {
            for window in windows.dropFirst() {
                window.close()
            }
        }

        // Style the primary window.
        if let window = windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.isRestorable = false
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
}
