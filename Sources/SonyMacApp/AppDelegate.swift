import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            let closingWindow = notification.object as? NSWindow
            Task { @MainActor in
                DockPresenceController.shared.hideFromDockIfNoWindowsRemain(excluding: closingWindow)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            if flag {
                DockPresenceController.shared.prepareForWindowPresentation()
                NSApp.activate(ignoringOtherApps: true)
            } else {
                DockPresenceController.shared.requestMainWindowPresentation()
            }
        }
        return true
    }
}
