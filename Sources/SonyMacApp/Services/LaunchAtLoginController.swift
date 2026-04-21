import Foundation
import Observation
import ServiceManagement

@Observable
@MainActor
final class LaunchAtLoginController {
    private static let automaticEnableAttemptedKey = "SonyAudioLaunchAtLoginAutomaticEnableAttempted"

    var isEnabled = false
    var statusMessage = "Launch at login is off."

    init() {
        refresh()
        includeByDefaultIfPossible()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            switch status {
            case .enabled:
                isEnabled = true
                statusMessage = "Launch at login is enabled."
            case .requiresApproval:
                isEnabled = false
                statusMessage = "Login item needs approval in System Settings."
            case .notFound:
                isEnabled = false
                statusMessage = "Launch at login is only available from a bundled app."
            case .notRegistered:
                isEnabled = false
                statusMessage = "Launch at login is off."
            @unknown default:
                isEnabled = false
                statusMessage = "Launch at login status is unavailable."
            }
        } else {
            isEnabled = false
            statusMessage = "Launch at login requires macOS 13 or newer."
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            statusMessage = "Launch at login requires macOS 13 or newer."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        refresh()
    }

    private func includeByDefaultIfPossible() {
        guard #available(macOS 13.0, *) else { return }
        guard !UserDefaults.standard.bool(forKey: Self.automaticEnableAttemptedKey) else { return }

        switch SMAppService.mainApp.status {
        case .enabled:
            UserDefaults.standard.set(true, forKey: Self.automaticEnableAttemptedKey)
        case .notRegistered:
            UserDefaults.standard.set(true, forKey: Self.automaticEnableAttemptedKey)

            do {
                try SMAppService.mainApp.register()
            } catch {
                statusMessage = error.localizedDescription
            }

            refresh()
        case .requiresApproval:
            UserDefaults.standard.set(true, forKey: Self.automaticEnableAttemptedKey)
            refresh()
        case .notFound:
            break
        @unknown default:
            break
        }
    }
}
