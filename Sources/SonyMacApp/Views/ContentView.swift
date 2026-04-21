import SwiftUI

struct ContentView: View {
    @Bindable var session: SonyHeadphoneSession
    @State private var showSplash = true
    @State private var contentOpacity = 0.0
    @State private var startupTaskStarted = false

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 1320

            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    Group {
                        if isCompact {
                            VStack(alignment: .leading, spacing: AppTheme.largeSectionSpacing) {
                                sidebar(compact: true)
                                mainPanel(compact: true)
                            }
                        } else {
                            HStack(alignment: .top, spacing: AppTheme.largeSectionSpacing) {
                                sidebar(compact: false)
                                mainPanel(compact: false)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(AppTheme.sectionPadding)
                    .animation(AppTheme.standardAnimation, value: isCompact)
                }
                .opacity(contentOpacity)

                if showSplash {
                    StartupSplashView()
                    .transition(.opacity)
                    .zIndex(5)
                }

                if let guide = session.connectionRecoveryGuide {
                    ConnectionRecoveryDialog(
                        guide: guide,
                        retryAction: { session.retryConnectionRecoveryGuide() },
                        refreshAction: {
                            session.dismissConnectionRecoveryGuide()
                            session.refreshDevices()
                        },
                        dismissAction: { session.dismissConnectionRecoveryGuide() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(6)
                }
            }
        }
        .task {
            guard !startupTaskStarted else { return }
            startupTaskStarted = true
            await runStartupSequence()
        }
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.largeSectionSpacing) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sony Audio")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Native macOS control surface for your headphones")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Theme")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textMuted)

                    ThemeModeToggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassCard {
                VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Headsets")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Connected and paired Sony devices")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Button("Refresh") {
                            session.refreshDevices()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .disabled(session.state.isBusy)
                    }

                    if session.devices.isEmpty {
                        Text("No paired Sony devices were found. Pair the headset in macOS Bluetooth settings first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(session.devices) { device in
                            DeviceRow(
                                device: device,
                                isSelected: session.state.connectedDeviceID == device.id,
                                isBusy: session.state.isBusy,
                                connectAction: { session.connect(to: device) },
                                disconnectAction: { session.disconnect() }
                            )
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(session.state.connectionLabel, systemImage: "headphones")
                        .font(.headline)

                    StatusPill(
                        title: session.state.isBusy ? "Syncing" : "Status",
                        value: session.state.statusMessage,
                        tint: AppTheme.accentMuted
                    )

                    StatusPill(title: "Battery", value: session.state.batteryText, tint: AppTheme.accentMuted)
                    StatusPill(
                        title: "Volume",
                        value: "\(Int(session.state.volumeLevel.rounded())) / \(HeadphoneState.volumeLevelRange.upperBound)",
                        tint: AppTheme.accentMuted
                    )

                    Text("A native XM6 control surface with direct macOS RFCOMM transport.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: compact ? .infinity : 300, alignment: .topLeading)
    }

    private func mainPanel(compact: Bool) -> some View {
        VStack(spacing: AppTheme.largeSectionSpacing) {
            NoiseControlHeroStage(
                mode: session.state.noiseControlMode,
                ambientLevel: Int(session.state.ambientLevel.rounded()),
                focusOnVoice: session.state.focusOnVoice,
                isConnected: session.state.connectedDeviceID != nil,
                compact: compact,
                connectionLabel: session.state.connectionLabel,
                transportSummary: session.state.connectedDeviceID == nil
                    ? "Select your paired XM6 from the left rail."
                    : "Live control is routed over Sony's verified XM6 RFCOMM channel.",
                modeChipLabel: session.state.noiseControlMode.rawValue,
                ambientChipLabel: session.state.noiseControlMode == .ambient && session.state.focusOnVoice
                    ? "Voice Focus"
                    : "Standard Ambient",
                dseeChipLabel: session.state.dseeExtreme ? "DSEE On" : "DSEE Off"
            )

            if compact {
                VStack(spacing: AppTheme.largeSectionSpacing) {
                    NoiseControlCard(session: session)
                        .disabled(session.state.isBusy)
                    VolumeCard(session: session)
                        .disabled(session.state.isBusy)
                    SoundEnhancementCard(session: session)
                        .disabled(session.state.isBusy)
                    ExperimentalControlsCard(session: session)
                        .disabled(session.state.isBusy)
                    CapabilityCard(support: session.state.support)
                }
            } else {
                HStack(alignment: .top, spacing: AppTheme.largeSectionSpacing) {
                    NoiseControlCard(session: session)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .disabled(session.state.isBusy)
                    VolumeCard(session: session)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .disabled(session.state.isBusy)
                    SoundEnhancementCard(session: session)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .disabled(session.state.isBusy)
                }

                ExperimentalControlsCard(session: session)
                    .disabled(session.state.isBusy)

                CapabilityCard(support: session.state.support)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 2)
    }
}

private extension ContentView {
    func runStartupSequence() async {
        async let bootstrap: Void = session.bootstrapIfNeeded()
        async let minimumPresentation: Void = minimumSplashPresentation()
        _ = await (bootstrap, minimumPresentation)

        withAnimation(.easeInOut(duration: 0.3)) {
            contentOpacity = 1
            showSplash = false
        }
    }

    func minimumSplashPresentation() async {
        try? await Task.sleep(for: .milliseconds(1200))
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AppTheme.panelPadding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .fill(AppTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 24, y: 8)
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .fill(AppTheme.cardFillSecondary)
        )
    }
}

private struct DeviceRow: View {
    let device: SonyDevice
    let isSelected: Bool
    let isBusy: Bool
    let connectAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(device.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button(isSelected ? "Disconnect" : "Connect") {
                isSelected ? disconnectAction() : connectAction()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? AppTheme.controlFill : AppTheme.controlFillActive)
            )
            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.panel)
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.controlStroke : AppTheme.controlFillActive.opacity(0.45), lineWidth: 1)
            )
            .disabled(isBusy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .fill(AppTheme.cardFillSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .stroke(isSelected ? AppTheme.accent.opacity(0.18) : AppTheme.controlStroke, lineWidth: 1)
        )
    }
}

private struct ConnectionRecoveryDialog: View {
    let guide: ConnectionRecoveryGuide
    let retryAction: () -> Void
    let refreshAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissAction)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.controlFillActive.opacity(0.18))
                            .frame(width: 42, height: 42)

                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(guide.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(guide.isAutomatic ? "Triggered during auto-connect" : "Triggered during a manual connection attempt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textMuted)
                    }

                    Spacer()

                    Button(action: dismissAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(AppTheme.controlFill)
                            )
                    }
                    .buttonStyle(.plain)
                }

                recoverySection(title: "What happened", body: guide.summary)
                recoverySection(title: "Why it usually happens", body: guide.likelyCause)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Next steps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(Array(guide.nextSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.panel)
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(AppTheme.accent)
                                )

                            Text(step)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Technical detail")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textMuted)

                    Text(guide.technicalDetail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                        .fill(AppTheme.cardFillSecondary)
                )

                HStack(spacing: 10) {
                    Button("Dismiss", action: dismissAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18)
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

                    Button("Refresh", action: refreshAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18)
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

                    Spacer()

                    Button(guide.retryButtonTitle, action: retryAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(AppTheme.controlFillActive)
                        )
                        .foregroundStyle(AppTheme.panel)
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.controlFillActive.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .padding(24)
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow.opacity(1.4), radius: 32, y: 16)
            .padding(28)
        }
    }

    private func recoverySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(body)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NoiseControlCard: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Noise Control",
                    subtitle: "ANC, Ambient Sound, and stable voice focus"
                )

                ModeSelector(
                    selection: Binding(
                        get: { session.state.noiseControlMode },
                        set: { session.applyNoiseControlMode($0) }
                    )
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Ambient Level")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(session.state.ambientLevel.rounded()))")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }

                    PrecisionSlider(
                        value: Binding(
                            get: { session.state.ambientLevel },
                            set: { session.applyAmbientLevel($0) }
                        ),
                        in: Double(NoiseControlMode.ambientLevelRange.lowerBound) ... Double(NoiseControlMode.ambientLevelRange.upperBound),
                        step: 1
                    )
                    .disabled(session.state.noiseControlMode != .ambient)
                }

                ControlToggle(
                    title: "Focus on Voice",
                    subtitle: "Keeps speech clearer in Ambient mode.",
                    isOn: Binding(
                        get: { session.state.noiseControlMode == .ambient && session.state.focusOnVoice },
                        set: { session.applyFocusOnVoice($0) }
                    )
                )
                .disabled(session.state.noiseControlMode != .ambient)

                Text(session.state.noiseControlMode.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct SoundEnhancementCard: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Enhancement",
                    subtitle: "DSEE and speak-to-chat"
                )

                SupportedToggle(
                    title: "DSEE Extreme",
                    subtitle: "Upscales compressed audio on supported models.",
                    isOn: Binding(
                        get: { session.state.dseeExtreme },
                        set: { session.applyDSEEExtreme($0) }
                    ),
                    availability: session.state.support.dseeExtreme
                )

                SupportedToggle(
                    title: "Speak-to-Chat",
                    subtitle: "Drops playback when you start talking.",
                    isOn: Binding(
                        get: { session.state.speakToChat },
                        set: { session.applySpeakToChat($0) }
                    ),
                    availability: session.state.support.speakToChat
                )
            }
        }
    }
}

private struct ExperimentalControlsCard: View {
    @Bindable var session: SonyHeadphoneSession

    private var isConnected: Bool {
        session.state.connectedDeviceID != nil
    }

    private var isNoiseCancellingActive: Bool {
        session.state.noiseControlMode == .noiseCancelling
    }

    private var experimentalVoiceFocusEnabled: Bool {
        isNoiseCancellingActive && session.state.focusOnVoice
    }

    private var guidanceText: String {
        if !isConnected {
            return "Connect your XM6 first. Experimental controls stay separate from the main feature set so they are always clearly opt-in."
        }

        if !isNoiseCancellingActive {
            return "Select Noise Cancelling above to try this experiment. The stable Ambient voice-focus control remains in the main Noise Control card."
        }

        return "This sends the headset's native voice-focus bit while ANC stays active. XM6 firmware may accept it, ignore it, or normalize it back on the next notify packet."
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Experimental",
                    subtitle: "Opt-in controls under live hardware validation"
                )

                HStack(spacing: 8) {
                    Text("Labs")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.panel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(AppTheme.accent)
                        )

                    Text("Separate from the stable feature surface by design.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ControlToggle(
                    title: "Voice Focus with ANC",
                    subtitle: "Attempts to keep voice emphasis active while Noise Cancelling stays on.",
                    isOn: Binding(
                        get: { experimentalVoiceFocusEnabled },
                        set: { session.applyExperimentalNoiseCancellingVoiceFocus($0) }
                    )
                )
                .disabled(!isConnected || !isNoiseCancellingActive)

                Text(guidanceText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct VolumeCard: View {
    @Bindable var session: SonyHeadphoneSession

    private var volumeAvailabilityMessage: String? {
        if session.state.connectedDeviceID == nil {
            return "Connect your XM6 to change its onboard volume."
        }

        if case let .unsupported(reason) = session.state.support.volume {
            return reason
        }

        return nil
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Volume",
                    subtitle: "Playback level over the XM6 control channel"
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Headphone Level")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(session.state.volumeLevel.rounded())) / \(HeadphoneState.volumeLevelRange.upperBound)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }

                    PrecisionSlider(
                        value: Binding(
                            get: { session.state.volumeLevel },
                            set: { session.applyVolumeLevel($0) }
                        ),
                        in: Double(HeadphoneState.volumeLevelRange.lowerBound) ... Double(HeadphoneState.volumeLevelRange.upperBound),
                        step: 1
                    )
                    .disabled(session.state.connectedDeviceID == nil || !session.state.support.volume.isSupported)
                }

                if let volumeAvailabilityMessage {
                    Text(volumeAvailabilityMessage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text("The external XM6 web controller confirms this same `0xA8` channel, so the slider is backed by Sony's native volume command.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}

private struct CapabilityCard: View {
    let support: FeatureSupport

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Driver Coverage",
                    subtitle: "What the current macOS driver can reach"
                )

                CapabilityRow(name: "Noise Control", availability: support.noiseControl)
                CapabilityRow(name: "Ambient Level", availability: support.ambientLevel)
                CapabilityRow(name: "Voice Focus", availability: support.focusOnVoice)
                CapabilityRow(name: "Volume", availability: support.volume)
                CapabilityRow(name: "DSEE Extreme", availability: support.dseeExtreme)
                CapabilityRow(name: "Speak-to-Chat", availability: support.speakToChat)
            }
        }
    }
}

private struct SupportedToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let availability: FeatureAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ControlToggle(title: title, subtitle: subtitle, isOn: $isOn)
            .disabled(!availability.isSupported)

            if case let .unsupported(reason) = availability {
                Text(reason)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textMuted)
            }
        }
    }
}

private struct CapabilityRow: View {
    let name: String
    let availability: FeatureAvailability

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            switch availability {
            case .supported:
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            case .unsupported:
                Text("Unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ModeSelector: View {
    @Binding var selection: NoiseControlMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NoiseControlMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selection == mode ? AppTheme.panel : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(selection == mode ? AppTheme.controlFillActive : AppTheme.controlFill)
                )
                .overlay(
                    Capsule()
                        .stroke(selection == mode ? AppTheme.controlFillActive.opacity(0.45) : AppTheme.controlStroke, lineWidth: 1)
                )
            }
        }
    }
}

private struct PrecisionSlider: View {
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
                    .frame(height: 3)

                Capsule()
                    .fill(isEnabled ? AppTheme.accent : AppTheme.disabled)
                    .frame(width: clampedX, height: 3)

                Circle()
                    .fill(isEnabled ? AppTheme.accent : AppTheme.disabled)
                    .frame(width: 10, height: 10)
                    .shadow(color: isEnabled ? AppTheme.accent.opacity(0.4) : .clear, radius: 6)
                    .offset(x: clampedX - 5)
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
        .frame(height: 10)
    }
}

private struct ControlToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(AppTheme.standardAnimation) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textMuted)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? AppTheme.accent : AppTheme.toggleOff)
                        .frame(width: 42, height: 24)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(AppTheme.standardAnimation, value: isOn)
    }
}

func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
        Text(subtitle)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppTheme.textSecondary)
    }
}

private extension FeatureAvailability {
    var isSupported: Bool {
        if case .supported = self {
            return true
        }
        return false
    }
}
