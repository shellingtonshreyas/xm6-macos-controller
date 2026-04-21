import AppKit
import ServiceManagement
import SwiftUI

@main
struct SonyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.dark.rawValue
    @State private var session = SonyHeadphoneSession()
    @State private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(session: session)
                .preferredColorScheme(preferredColorScheme)
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1360, height: 860)

        MenuBarExtra {
            MenuBarResidentView(session: session, launchAtLogin: launchAtLogin)
                .preferredColorScheme(preferredColorScheme)
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
}
