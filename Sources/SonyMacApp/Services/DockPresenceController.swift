import AppKit

/// Keeps Sony Audio visible in the Dock only while a main window is open.
/// Closing the last titled window switches to `.accessory` so the process stays
/// alive in the menu bar without occupying Dock or Command-Tab slots.
@MainActor
final class DockPresenceController {
    static let shared = DockPresenceController()
    static let reopenMainWindowNotification = Notification.Name("SonyAudioReopenMainWindow")

    private init() {}

    func prepareForWindowPresentation() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    func requestMainWindowPresentation() {
        prepareForWindowPresentation()
        NotificationCenter.default.post(name: Self.reopenMainWindowNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from `NSWindow.willCloseNotification`. Defers the check so the
    /// closing window is already gone from `NSApp.windows` before we decide.
    func hideFromDockIfNoWindowsRemain(excluding closingWindow: NSWindow?) {
        DispatchQueue.main.async { [weak self] in
            self?.applyAccessoryPolicyIfNeeded(excluding: closingWindow)
        }
    }

    private func applyAccessoryPolicyIfNeeded(excluding closingWindow: NSWindow?) {
        let remainingDockWindows = NSApp.windows.filter { window in
            guard window !== closingWindow else { return false }
            return Self.isDockVisibleWindow(window)
        }

        guard remainingDockWindows.isEmpty else { return }
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// MenuBarExtra `.window` panels are NSPanels and must not count as Dock windows.
    private static func isDockVisibleWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        guard !(window is NSPanel) else { return false }
        return window.styleMask.contains(.titled)
    }
}
