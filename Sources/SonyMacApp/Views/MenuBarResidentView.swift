import AppKit
import SwiftUI

struct MenuBarResidentView: View {
    @Bindable var session: SonyHeadphoneSession
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Environment(\.openWindow) private var openWindow

    private var isScreenshotBuild: Bool {
        session.isScreenshotBuild
    }

    private var hasMacConnectedDevice: Bool {
        session.hasMacConnectedDevice
    }

    private var hasUsableHeadsetConnection: Bool {
        session.hasUsableHeadsetConnection
    }

    private var selectedDevice: SonyDevice? {
        if let connectedID = session.state.connectedDeviceID,
           let match = session.devices.first(where: { $0.id == connectedID }) {
            return match
        }

        if let macConnected = session.devices.first(where: { $0.isConnected }) {
            return macConnected
        }

        return session.devices.first
    }

    private var deviceTitle: String {
        selectedDevice?.name ?? "Sony Headphones"
    }

    private var headerSubtitle: String {
        if session.state.connectedDeviceID != nil {
            return "Live control open"
        }

        if hasMacConnectedDevice {
            return "Ready in macOS"
        }

        if selectedDevice != nil {
            return "Connect in macOS to continue"
        }

        return "No Sony headset paired"
    }

    private var connectionButtonTitle: String {
        if session.state.connectedDeviceID != nil {
            return "Close"
        }

        return hasMacConnectedDevice ? "Open Control" : "Connect in macOS"
    }

    private var batteryDisplayText: String {
        session.state.batteryText == "Unknown" ? "--" : session.state.batteryText
    }

    private var volumeControlAvailable: Bool {
        if case .supported = session.state.support.volume {
            return true
        }
        return false
    }

    private var dseeSupported: Bool {
        if case .supported = session.state.support.dseeExtreme {
            return true
        }
        return false
    }

    private var speakToChatSupported: Bool {
        if case .supported = session.state.support.speakToChat {
            return true
        }
        return false
    }

    private var launchAtLoginStatusLine: String? {
        if let confirmationMessage = launchAtLogin.confirmationMessage {
            return confirmationMessage
        }

        switch launchAtLogin.statusMessage {
        case "Login item needs approval in System Settings.",
             "Launch at login requires macOS 13 or newer.":
            return launchAtLogin.statusMessage
        default:
            return nil
        }
    }

    private var footerMessage: String? {
        if session.state.isBusy {
            return session.state.statusMessage
        }

        if let launchAtLoginStatusLine {
            return launchAtLoginStatusLine
        }

        if session.devices.isEmpty {
            return "Pair a Sony headset in macOS Bluetooth settings first."
        }

        if !hasMacConnectedDevice {
            return "Connect your headset in macOS to unlock live controls."
        }

        return nil
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                controlsSection
                actionsSection

                if let footerMessage {
                    divider

                    Text(footerMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: isScreenshotBuild ? 344 : 316)
        .foregroundStyle(AppTheme.textPrimary)
        .task {
            session.refreshDevices()
            launchAtLogin.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SONY AUDIO")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2.2)
                        .foregroundStyle(AppTheme.textMuted)

                    Text(deviceTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(headerSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ThemeModeToggle()
            }

            HStack(spacing: 8) {
                statusChip(label: "Battery", value: batteryDisplayText)

                if hasUsableHeadsetConnection {
                    statusChip(label: "Mode", value: session.state.noiseControlMode.menuBarStatusLabel)
                }

                Spacer(minLength: 8)

                Button(connectionButtonTitle) {
                    if session.state.connectedDeviceID == nil {
                        session.connectPreferredDevice()
                    } else {
                        session.disconnect()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: session.state.connectedDeviceID == nil ? .semibold : .medium))
                .padding(.horizontal, session.state.connectedDeviceID == nil ? 16 : 14)
                .padding(.vertical, session.state.connectedDeviceID == nil ? 9 : 8)
                .background(
                    Capsule()
                        .fill(session.state.connectedDeviceID == nil ? AppTheme.controlFillActive : AppTheme.controlFill)
                )
                .foregroundStyle(session.state.connectedDeviceID == nil ? AppTheme.panel : AppTheme.textSecondary)
                .overlay(
                    Capsule()
                        .stroke(session.state.connectedDeviceID == nil ? AppTheme.controlFillActive.opacity(0.42) : AppTheme.controlStroke, lineWidth: 1)
                )
                .disabled(session.state.isBusy)
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            divider

            VStack(alignment: .leading, spacing: 10) {
                sectionEyebrow("MODE")

                MenuBarModeSelector(
                    selection: Binding(
                        get: { session.state.noiseControlMode },
                        set: { session.applyNoiseControlMode($0) }
                    )
                )
            }
            .disabled(!hasUsableHeadsetConnection)

            if session.state.noiseControlMode == .ambient {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionEyebrow("AMBIENT")

                        Spacer()

                        Text("\(Int(session.state.ambientLevel.rounded())) / \(NoiseControlMode.ambientLevelRange.upperBound)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    MonolithSlider(
                        value: Binding(
                            get: { session.state.ambientLevel },
                            set: { session.applyAmbientLevel($0) }
                        ),
                        in: Double(NoiseControlMode.ambientLevelRange.lowerBound) ... Double(NoiseControlMode.ambientLevelRange.upperBound),
                        step: 1
                    )

                    compactToggle(
                        title: "Focus on Voice",
                        isOn: Binding(
                            get: { session.state.focusOnVoice },
                            set: { session.applyFocusOnVoice($0) }
                        )
                    )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius + 6, style: .continuous)
                        .fill(AppTheme.cardFillSecondary)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionEyebrow("VOLUME")

                    Spacer()

                    Text("\(Int(session.state.volumeLevel.rounded())) / \(HeadphoneState.volumeLevelRange.upperBound)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                MonolithSlider(
                    value: Binding(
                        get: { session.state.volumeLevel },
                        set: { session.applyVolumeLevel($0) }
                    ),
                    in: Double(HeadphoneState.volumeLevelRange.lowerBound) ... Double(HeadphoneState.volumeLevelRange.upperBound),
                    step: 1
                )
                .disabled(!hasUsableHeadsetConnection || !volumeControlAvailable)
            }

            enhancementToggles
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            divider

            HStack(spacing: 10) {
                utilityButton("Open App") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                utilityButton("Diagnostics") {
                    session.copyDiagnosticsReport()
                }
            }

            HStack {
                Button("Refresh") {
                    session.refreshDevices()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(session.state.isBusy)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func statusChip(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AppTheme.controlFill)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.controlStroke, lineWidth: 1)
        )
    }

    private func compactToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue ? AppTheme.accent : AppTheme.toggleOff)
                        .frame(width: 44, height: 24)

                    Circle()
                        .fill(AppTheme.switchThumb)
                        .frame(width: 20, height: 20)
                        .padding(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.cardFillSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var enhancementToggles: some View {
        if isScreenshotBuild {
            VStack(spacing: 10) {
                dseeToggle
                speakToChatToggle
            }
        } else {
            HStack(spacing: 10) {
                dseeToggle
                speakToChatToggle
            }
        }
    }

    private var dseeToggle: some View {
        compactToggle(
            title: "DSEE",
            isOn: Binding(
                get: { session.state.dseeExtreme },
                set: { session.applyDSEEExtreme($0) }
            )
        )
        .disabled(!hasUsableHeadsetConnection || !dseeSupported)
    }

    private var speakToChatToggle: some View {
        compactToggle(
            title: isScreenshotBuild ? "Speak to Chat" : "Speak-to-Chat",
            isOn: Binding(
                get: { session.state.speakToChat },
                set: { session.applySpeakToChat($0) }
            )
        )
        .disabled(!hasUsableHeadsetConnection || !speakToChatSupported)
    }

    private var divider: some View {
        Divider()
            .overlay(AppTheme.divider)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(AppTheme.textMuted)
    }

    private func utilityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(AppTheme.controlFill)
            )
            .foregroundStyle(AppTheme.textPrimary)
            .overlay(
                Capsule()
                    .stroke(AppTheme.controlStroke, lineWidth: 1)
            )
    }
}

private struct MenuBarModeSelector: View {
    @Binding var selection: NoiseControlMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NoiseControlMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.menuBarButtonLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == mode ? AppTheme.panel : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(selection == mode ? AppTheme.accent : AppTheme.controlFill)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == mode ? AppTheme.accent.opacity(0.4) : AppTheme.controlStroke, lineWidth: 1)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardFillSecondary)
        )
    }
}

private extension NoiseControlMode {
    var menuBarButtonLabel: String {
        switch self {
        case .noiseCancelling:
            return "ANC"
        case .ambient:
            return "Ambient"
        case .off:
            return "Off"
        }
    }

    var menuBarStatusLabel: String {
        switch self {
        case .noiseCancelling:
            return "ANC"
        case .ambient:
            return "AMB"
        case .off:
            return "Off"
        }
    }
}
