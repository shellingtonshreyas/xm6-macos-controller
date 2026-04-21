import SwiftUI

struct MonolithControlSurface: View {
    @Bindable var session: SonyHeadphoneSession
    @Bindable var launchAtLogin: LaunchAtLoginController
    let compact: Bool

    private var isScreenshotBuild: Bool {
        session.isScreenshotBuild
    }

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

    private var batteryDisplayText: String {
        session.state.batteryText == "Unknown" ? "--" : session.state.batteryText
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
                HStack(spacing: 10) {
                    headerStatusPill
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
                .foregroundStyle(hasLiveControl ? AppTheme.textPrimary : AppTheme.panel)
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

                    if !isScreenshotBuild, let launchAtLoginStatusLine {
                        Text(launchAtLoginStatusLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    private var headerStatusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hasUsableConnection ? AppTheme.accent : AppTheme.textMuted.opacity(0.4))
                .frame(width: 7, height: 7)

            Text(batteryDisplayText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppTheme.controlFill)
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.controlStroke, lineWidth: 1)
        )
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
                    .font(.system(size: compact ? 12 : 13, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
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

                MonolithHeadphoneGlyph(palette: palette, compact: compact)
                    .frame(width: compact ? 248 : 292, height: compact ? 196 : 228)
                    .offset(x: width * 0.12, y: compact ? 10 : 4)

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

private struct MonolithHeadphoneGlyph: View {
    let palette: MonolithPalette
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cupWidth = width * 0.22
            let cupHeight = height * 0.52
            let cupInset = cupWidth * 0.14
            let cupOffset = width * 0.24
            let headbandTop = height * 0.08
            let headbandBottom = height * 0.64
            let stemTop = height * 0.34
            let stemBottom = height * 0.58
            let centerPadWidth = width * 0.22
            let centerPadHeight = height * 0.16

            ZStack {
                Ellipse()
                    .fill(palette.tint.opacity(0.08))
                    .frame(width: width * 0.64, height: height * 0.74)
                    .blur(radius: compact ? 24 : 30)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.18, y: headbandBottom))
                    path.addCurve(
                        to: CGPoint(x: width * 0.82, y: headbandBottom),
                        control1: CGPoint(x: width * 0.24, y: headbandTop),
                        control2: CGPoint(x: width * 0.76, y: headbandTop)
                    )
                }
                .stroke(palette.stroke.opacity(0.92), style: StrokeStyle(lineWidth: compact ? 11 : 13, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.18, y: headbandBottom))
                    path.addCurve(
                        to: CGPoint(x: width * 0.82, y: headbandBottom),
                        control1: CGPoint(x: width * 0.26, y: headbandTop + height * 0.05),
                        control2: CGPoint(x: width * 0.74, y: headbandTop + height * 0.05)
                    )
                }
                .stroke(AppTheme.heroStageSheen.opacity(0.75), style: StrokeStyle(lineWidth: compact ? 3.5 : 4.5, lineCap: .round))
                .blur(radius: 0.4)

                Capsule()
                    .fill(AppTheme.heroStagePad.opacity(0.2))
                    .frame(width: centerPadWidth, height: centerPadHeight)
                    .offset(y: height * 0.06)

                Capsule()
                    .stroke(AppTheme.heroStageDivider.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, dash: [8, 12]))
                    .frame(width: width * 0.72, height: height * 0.42)
                    .offset(y: height * 0.14)

                headphoneCup(cupWidth: cupWidth, cupHeight: cupHeight, inset: cupInset)
                    .offset(x: -cupOffset, y: height * 0.22)

                headphoneCup(cupWidth: cupWidth, cupHeight: cupHeight, inset: cupInset)
                    .offset(x: cupOffset, y: height * 0.22)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.29, y: stemTop))
                    path.addLine(to: CGPoint(x: width * 0.25, y: stemBottom))
                    path.move(to: CGPoint(x: width * 0.71, y: stemTop))
                    path.addLine(to: CGPoint(x: width * 0.75, y: stemBottom))
                }
                .stroke(AppTheme.heroStageShellSecondary.opacity(0.9), style: StrokeStyle(lineWidth: compact ? 7 : 8, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.29, y: stemTop + 1))
                    path.addLine(to: CGPoint(x: width * 0.25, y: stemBottom - 1))
                    path.move(to: CGPoint(x: width * 0.71, y: stemTop + 1))
                    path.addLine(to: CGPoint(x: width * 0.75, y: stemBottom - 1))
                }
                .stroke(AppTheme.heroStageSheen.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    private func headphoneCup(cupWidth: CGFloat, cupHeight: CGFloat, inset: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cupWidth * 0.34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.heroStageShellSecondary.opacity(0.9),
                            AppTheme.heroStagePadInner.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cupWidth * 0.34, style: .continuous)
                .stroke(palette.stroke.opacity(0.72), lineWidth: 1.5)

            RoundedRectangle(cornerRadius: (cupWidth - (inset * 2)) * 0.34, style: .continuous)
                .fill(AppTheme.heroStagePadInner.opacity(0.92))
                .padding(inset)

            RoundedRectangle(cornerRadius: (cupWidth - (inset * 2)) * 0.34, style: .continuous)
                .stroke(AppTheme.heroStageSheen.opacity(0.26), lineWidth: 1)
                .padding(inset + 1)

            VStack(spacing: 6) {
                Capsule()
                    .fill(palette.stroke.opacity(0.7))
                    .frame(width: cupWidth * 0.22, height: 3)

                Capsule()
                    .fill(palette.stroke.opacity(0.52))
                    .frame(width: cupWidth * 0.27, height: 3)

                Capsule()
                    .fill(palette.stroke.opacity(0.38))
                    .frame(width: cupWidth * 0.19, height: 3)
            }
        }
        .frame(width: cupWidth, height: cupHeight)
        .shadow(color: AppTheme.shadow.opacity(0.55), radius: compact ? 12 : 16, y: 10)
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
