import AppKit
import ServiceManagement
import SwiftUI

@main
struct SonyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SonyHeadphoneSession()
    @State private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(session: session)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1360, height: 860)

        MenuBarExtra {
            MenuBarResidentView(session: session, launchAtLogin: launchAtLogin)
                .preferredColorScheme(.dark)
        } label: {
            Label(menuBarTitle, systemImage: session.state.connectedDeviceID == nil ? "headphones" : "headphones.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTitle: String {
        guard session.state.connectedDeviceID != nil else {
            return "Sony"
        }

        if session.state.batteryText == "Unknown" {
            return "Sony"
        }

        return "Sony \(session.state.batteryText)"
    }
}
