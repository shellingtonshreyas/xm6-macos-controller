import SwiftUI

struct MonolithControlSurface: View {
    @Bindable var session: SonyHeadphoneSession
    let compact: Bool

    private var hasLiveControl: Bool {
        session.state.connectedDeviceID != nil
    }

    private var hasUsableConnection: Bool {
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

    private var headerStatusLine: String {
        if hasLiveControl {
            return "Connected in macOS • Live control open"
        }

        if session.hasMacConnectedDevice {
            return "Connected in macOS • Ready to open control"
        }

        if selectedDevice != nil {
            return "Paired on this Mac • Connect in macOS to continue"
        }

        return "No Sony headset paired on this Mac"
    }

    private var connectionButtonTitle: String {
        if hasLiveControl {
            return "Close"
        }

        return session.hasMacConnectedDevice ? "Open Control" : "Connect in macOS"
    }

    private var heroTransportSummary: String {
        if hasLiveControl {
            return "Live control is routed through the Sony channel. Everything visible stays inside one focused surface."
        }

        if session.hasMacConnectedDevice {
            return "Headset audio is already connected in macOS. Open the Sony control channel to sync live state."
        }

        return "Choose a paired Sony headset below, then open the control surface."
    }

    private var volumeSupported: Bool {
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

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: compact ? 24 : 28) {
                header
                hero
                controlsSection
                deviceSection
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SONY AUDIO")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(2.4)
                    .foregroundStyle(AppTheme.textMuted)

                Text(deviceTitle)
                    .font(.system(size: compact ? 24 : 28, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(headerStatusLine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hasUsableConnection ? AppTheme.accent : AppTheme.textMuted.opacity(0.4))
                            .frame(width: 8, height: 8)

                        Text(session.state.batteryText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    ThemeModeToggle()
                }

                Button(connectionButtonTitle) {
                    if hasLiveControl {
                        session.disconnect()
                    } else {
                        session.connectPreferredDevice()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: hasLiveControl ? .medium : .semibold))
                .padding(.horizontal, hasLiveControl ? 14 : 18)
                .padding(.vertical, hasLiveControl ? 8 : 10)
                .background(
                    Capsule()
                        .fill(hasLiveControl ? AppTheme.controlFill : AppTheme.controlFillActive)
                )
                .foregroundStyle(hasLiveControl ? AppTheme.textSecondary : AppTheme.panel)
                .overlay(
                    Capsule()
                        .stroke(hasLiveControl ? AppTheme.controlStroke : AppTheme.controlFillActive.opacity(0.42), lineWidth: 1)
                )
                .disabled(session.state.isBusy)
            }
        }
    }

    private var hero: some View {
        MonolithHeroPanel(
            mode: session.state.noiseControlMode,
            transportSummary: heroTransportSummary,
            compact: compact
        )
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
                .overlay(AppTheme.divider)

            VStack(alignment: .leading, spacing: 10) {
                Text("MODE")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.textMuted)

                MonolithModeSelector(
                    selection: Binding(
                        get: { session.state.noiseControlMode },
                        set: { session.applyNoiseControlMode($0) }
                    )
                )
            }

            if session.state.noiseControlMode == .ambient {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ambient Level")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(session.state.ambientLevel.rounded())) / \(NoiseControlMode.ambientLevelRange.upperBound)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }

                    MonolithSlider(
                        value: Binding(
                            get: { session.state.ambientLevel },
                            set: { session.applyAmbientLevel($0) }
                        ),
                        in: Double(NoiseControlMode.ambientLevelRange.lowerBound) ... Double(NoiseControlMode.ambientLevelRange.upperBound),
                        step: 1
                    )

                    MonolithToggleRow(
                        title: "Focus on Voice",
                        subtitle: "Keeps speech clearer while Ambient stays open.",
                        isOn: Binding(
                            get: { session.state.focusOnVoice },
                            set: { session.applyFocusOnVoice($0) }
                        )
                    )
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius + 6, style: .continuous)
                        .fill(AppTheme.cardFillSecondary)
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("VOLUME")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(AppTheme.textMuted)
                    Spacer()
                    Text("\(Int(session.state.volumeLevel.rounded())) / \(HeadphoneState.volumeLevelRange.upperBound)")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
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
                .disabled(!hasUsableConnection || !volumeSupported)

                if !volumeSupported {
                    Text("Volume control is not available for the current session.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            ViewThatFits(in: compact ? .vertical : .horizontal) {
                HStack(spacing: 14) {
                    quickToggle("DSEE", subtitle: "Audio enhancement", isOn: Binding(
                        get: { session.state.dseeExtreme },
                        set: { session.applyDSEEExtreme($0) }
                    ))
                    .disabled(!hasUsableConnection || !dseeSupported)

                    quickToggle("Speak-to-Chat", subtitle: "Pause on speech", isOn: Binding(
                        get: { session.state.speakToChat },
                        set: { session.applySpeakToChat($0) }
                    ))
                    .disabled(!hasUsableConnection || !speakToChatSupported)
                }

                VStack(spacing: 14) {
                    quickToggle("DSEE", subtitle: "Audio enhancement", isOn: Binding(
                        get: { session.state.dseeExtreme },
                        set: { session.applyDSEEExtreme($0) }
                    ))
                    .disabled(!hasUsableConnection || !dseeSupported)

                    quickToggle("Speak-to-Chat", subtitle: "Pause on speech", isOn: Binding(
                        get: { session.state.speakToChat },
                        set: { session.applySpeakToChat($0) }
                    ))
                    .disabled(!hasUsableConnection || !speakToChatSupported)
                }
            }
        }
    }

    private func quickToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        MonolithToggleRow(title: title, subtitle: subtitle, isOn: isOn)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius + 6, style: .continuous)
                    .fill(AppTheme.cardFillSecondary)
            )
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(AppTheme.divider)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEVICES")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(AppTheme.textMuted)
                    Text(session.state.statusMessage)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Refresh") {
                    session.refreshDevices()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(session.state.isBusy)
            }

            if session.devices.isEmpty {
                Text("No paired Sony devices were found. Pair the headset in macOS Bluetooth settings first.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.devices) { device in
                            MonolithDeviceChip(
                                device: device,
                                isSelected: session.state.connectedDeviceID == device.id,
                                isBusy: session.state.isBusy,
                                action: {
                                    guard device.isConnected else {
                                        session.state.statusMessage = "Connect \(device.name) in macOS first."
                                        return
                                    }

                                    if session.state.connectedDeviceID == device.id {
                                        session.disconnect()
                                    } else {
                                        session.connect(to: device)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct MonolithHeroPanel: View {
    let mode: NoiseControlMode
    let transportSummary: String
    let compact: Bool

    private var palette: MonolithPalette {
        MonolithPalette(mode: mode)
    }

    private var heroTitle: String {
        switch mode {
        case .noiseCancelling:
            return "NOISE\nCANCELLING"
        case .ambient:
            return "AMBIENT\nSOUND"
        case .off:
            return "CONTROL\nOFF"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.cardFillSecondary,
                            AppTheme.cardFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.stroke.opacity(0.55), lineWidth: 1)

            LinearGradient(
                colors: [
                    palette.tint.opacity(0.16),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            MonolithContourField(palette: palette, compact: compact)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: compact ? 14 : 16) {
                Text(heroTitle)
                    .font(.system(size: compact ? 52 : 68, weight: .semibold))
                    .tracking(-1.2)
                    .lineSpacing(compact ? -6 : -10)
                    .foregroundStyle(AppTheme.textPrimary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)

                Text(mode.subtitle)
                    .font(.system(size: compact ? 14 : 16, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(transportSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textMuted)
                    .frame(maxWidth: compact ? .infinity : 360, alignment: .leading)
            }
            .padding(compact ? 24 : 30)
        }
        .frame(height: compact ? 320 : 360)
        .compositingGroup()
    }
}

struct MonolithContourField: View {
    let palette: MonolithPalette
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                Circle()
                    .fill(palette.tint.opacity(0.08))
                    .frame(width: width * 0.36, height: width * 0.36)
                    .blur(radius: 34)
                    .offset(x: width * 0.23, y: -height * 0.02)

                ForEach(0..<6, id: \.self) { index in
                    Ellipse()
                        .stroke(palette.stroke.opacity(0.24 - (Double(index) * 0.024)), lineWidth: 1)
                        .frame(
                            width: width * (0.54 + (CGFloat(index) * 0.06)),
                            height: height * (0.28 + (CGFloat(index) * 0.05))
                        )
                        .offset(x: width * 0.12, y: height * 0.02)
                }

                Image(systemName: "headphones")
                    .font(.system(size: compact ? 150 : 180, weight: .ultraLight))
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.22))
                    .offset(x: width * 0.12, y: compact ? 8 : 2)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.cardFill.opacity(0.88),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.38)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

struct MonolithModeSelector: View {
    @Binding var selection: NoiseControlMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NoiseControlMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == mode ? AppTheme.panel : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(selection == mode ? AppTheme.accent : AppTheme.controlFill)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == mode ? AppTheme.accent.opacity(0.4) : AppTheme.controlStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardFillSecondary)
        )
    }
}

struct MonolithSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @Environment(\.isEnabled) private var isEnabled

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        GeometryReader { geometry in
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let width = max(geometry.size.width, 1)
            let clampedX = min(max(normalized * width, 0), width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.sliderTrack)
                    .frame(height: 8)

                Capsule()
                    .fill(isEnabled ? AppTheme.accent : AppTheme.disabled)
                    .frame(width: clampedX, height: 8)

                Circle()
                    .fill(isEnabled ? AppTheme.switchThumb : AppTheme.disabled)
                    .frame(width: 24, height: 24)
                    .shadow(color: AppTheme.shadow.opacity(isEnabled ? 1 : 0), radius: 10, y: 4)
                    .offset(x: clampedX - 12)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let ratio = min(max(drag.location.x / width, 0), 1)
                        let raw = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: 24)
    }
}

struct MonolithToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard isEnabled else { return }
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textMuted)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? AppTheme.accent : AppTheme.toggleOff)
                        .frame(width: 54, height: 30)

                    Circle()
                        .fill(AppTheme.switchThumb)
                        .frame(width: 26, height: 26)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MonolithDeviceChip: View {
    let device: SonyDevice
    let isSelected: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(device.isConnected ? AppTheme.accent : AppTheme.textMuted.opacity(0.35))
                        .frame(width: 7, height: 7)

                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Text(isSelected ? "Live control open" : (device.isConnected ? "Open control channel" : "Connect in macOS"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? AppTheme.detailFill : AppTheme.cardFillSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.26) : AppTheme.controlStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

struct MonolithPalette {
    let tint: Color
    let stroke: Color

    init(mode: NoiseControlMode) {
        switch mode {
        case .noiseCancelling:
            tint = AppTheme.accent
            stroke = AppTheme.ancHighlight
        case .ambient:
            tint = AppTheme.ambientAccent
            stroke = AppTheme.ambientHighlight
        case .off:
            tint = AppTheme.offAccent
            stroke = AppTheme.offHighlight
        }
    }
}
