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
            VStack(alignment: .leading, spacing: 8) {
                Text("Sony Audio")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Native macOS control surface for your headphones")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }

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
            heroCard(compact: compact)

            if compact {
                VStack(spacing: AppTheme.largeSectionSpacing) {
                    NoiseControlCard(session: session)
                    SoundEnhancementCard(session: session)
                    CapabilityCard(support: session.state.support)
                }
            } else {
                HStack(alignment: .top, spacing: AppTheme.largeSectionSpacing) {
                    NoiseControlCard(session: session)
                    SoundEnhancementCard(session: session)
                }

                CapabilityCard(support: session.state.support)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    private func heroCard(compact: Bool) -> some View {
        GlassCard {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                        heroArtwork
                        heroText
                    }
                } else {
                    HStack(alignment: .center, spacing: AppTheme.panelPadding) {
                        heroArtwork
                        heroText
                        Spacer()
                    }
                }
            }
        }
    }
}

private extension ContentView {
    var heroArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .fill(AppTheme.cardFillSecondary)
                .frame(width: 104, height: 104)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )

            Image(systemName: "airpods.max")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var heroText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.state.connectionLabel)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(session.state.connectedDeviceID == nil ? "Select your paired XM6 from the left rail." : "Live control is routed over Sony's verified XM6 RFCOMM channel.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    heroChips
                }

                VStack(alignment: .leading, spacing: 10) {
                    heroChips
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var heroChips: some View {
        FeatureChip(title: session.state.noiseControlMode.rawValue, tint: AppTheme.accent)
        FeatureChip(title: session.state.focusOnVoice ? "Voice Focus" : "Standard Ambient", tint: AppTheme.accentMuted)
        FeatureChip(title: session.state.dseeExtreme ? "DSEE On" : "DSEE Off", tint: AppTheme.textPrimary, highlighted: false)
    }

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

private struct FeatureChip: View {
    let title: String
    let tint: Color
    var highlighted = true

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.controlFill)
            )
            .foregroundStyle(tint)
            .overlay(
                Capsule()
                    .stroke(highlighted ? tint.opacity(0.28) : AppTheme.controlStroke, lineWidth: 1)
            )
    }
}

private struct DeviceRow: View {
    let device: SonyDevice
    let isSelected: Bool
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

private struct NoiseControlCard: View {
    @Bindable var session: SonyHeadphoneSession

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppTheme.elementSpacing) {
                sectionHeader(
                    title: "Noise Control",
                    subtitle: "ANC, Ambient Sound, and voice focus"
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
                        in: 0 ... 19,
                        step: 1
                    )
                    .disabled(session.state.noiseControlMode != .ambient)
                }

                ControlToggle(
                    title: "Focus on Voice",
                    subtitle: "Keeps speech clearer in Ambient mode.",
                    isOn: Binding(
                    get: { session.state.focusOnVoice },
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
