import AppKit
import SwiftUI

struct MenuBarResidentView: View {
    @Bindable var session: SonyHeadphoneSession
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SONY")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(session.state.connectionLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(session.state.batteryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            Button(session.state.connectedDeviceID == nil ? "Connect XM6" : "Disconnect XM6") {
                if session.state.connectedDeviceID == nil {
                    session.connectPreferredDevice()
                } else {
                    session.disconnect()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(session.state.connectedDeviceID == nil ? AppTheme.controlFillActive : AppTheme.controlFill)
            )
            .foregroundStyle(session.state.connectedDeviceID == nil ? AppTheme.panel : AppTheme.textPrimary)
            .overlay(
                Capsule()
                    .stroke(session.state.connectedDeviceID == nil ? AppTheme.controlFillActive.opacity(0.45) : AppTheme.controlStroke, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Noise Control")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 8) {
                    quickModeButton(.noiseCancelling, title: "ANC")
                    quickModeButton(.ambient, title: "Ambient")
                    quickModeButton(.off, title: "Off")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                quickToggle(
                    title: "DSEE",
                    isOn: Binding(
                        get: { session.state.dseeExtreme },
                        set: { session.applyDSEEExtreme($0) }
                    )
                )

                quickToggle(
                    title: "Speak-to-Chat",
                    isOn: Binding(
                        get: { session.state.speakToChat },
                        set: { session.applySpeakToChat($0) }
                    )
                )
            }

            Toggle(
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Start in the background and auto-connect when XM6 appears.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(AppTheme.accent)

            HStack(spacing: 10) {
                Button("Open Control Surface") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
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

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.controlFill)
                )
                .foregroundStyle(AppTheme.textSecondary)
                .overlay(
                    Capsule()
                        .stroke(AppTheme.controlStroke, lineWidth: 1)
                )
            }

            Text(launchAtLogin.statusMessage)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textMuted)

            Text(session.state.statusMessage)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.panelPadding)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .fill(AppTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 24, y: 8)
        .foregroundStyle(AppTheme.textPrimary)
        .task {
            session.refreshDevices()
            launchAtLogin.refresh()
        }
    }

    private func quickModeButton(_ mode: NoiseControlMode, title: String) -> some View {
        Button(title) {
            session.applyNoiseControlMode(mode)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(session.state.noiseControlMode == mode ? AppTheme.controlFillActive : AppTheme.controlFill)
        )
        .overlay(
            Capsule()
                .stroke(session.state.noiseControlMode == mode ? AppTheme.controlFillActive.opacity(0.45) : AppTheme.controlStroke, lineWidth: 1)
        )
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(session.state.noiseControlMode == mode ? AppTheme.panel : AppTheme.textSecondary)
    }

    private func quickToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
        }
    }
}
