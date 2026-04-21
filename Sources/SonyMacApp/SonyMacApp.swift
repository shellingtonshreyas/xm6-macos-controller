import AppKit
import ServiceManagement
import SwiftUI

@main
struct SonyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.dark.rawValue
    @State private var session = SonyHeadphoneSession(runtimeMode: Self.runtimeMode)
    @State private var launchAtLogin = LaunchAtLoginController(automaticSetupEnabled: Self.runtimeMode == .live)

    init() {
        NSApplication.shared.appearance = Self.appAppearanceFromDefaults.nsAppearance
    }

    var body: some Scene {
        Window("Sony Audio", id: "main") {
            ContentView(session: session, launchAtLogin: launchAtLogin)
                .preferredColorScheme(preferredColorScheme)
                .task(id: storedAppearance) {
                    syncAppAppearance()
                }
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1360, height: 860)

        MenuBarExtra {
            MenuBarResidentView(session: session, launchAtLogin: launchAtLogin)
                .preferredColorScheme(preferredColorScheme)
                .task(id: storedAppearance) {
                    syncAppAppearance()
                }
        } label: {
            Label(menuBarTitle, systemImage: session.hasUsableHeadsetConnection ? "headphones.circle.fill" : "headphones")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTitle: String {
        guard session.hasUsableHeadsetConnection else {
            return "Sony"
        }

        if session.state.batteryText == "Unknown" {
            return "Sony"
        }

        return "Sony \(session.state.batteryText)"
    }

    private var preferredColorScheme: ColorScheme {
        AppAppearance(rawValue: storedAppearance)?.colorScheme ?? .dark
    }

    private static var runtimeMode: SonyAppRuntimeMode {
        let screenshotBuild = Bundle.main.object(forInfoDictionaryKey: "SonyScreenshotBuild") as? Bool ?? false
        return screenshotBuild ? .screenshot : .live
    }

    private static var appAppearanceFromDefaults: AppAppearance {
        let storedValue = UserDefaults.standard.string(forKey: AppAppearance.storageKey)
        return AppAppearance(rawValue: storedValue ?? "") ?? .dark
    }

    private func syncAppAppearance() {
        NSApplication.shared.appearance = AppAppearance(rawValue: storedAppearance)?.nsAppearance
    }
}
