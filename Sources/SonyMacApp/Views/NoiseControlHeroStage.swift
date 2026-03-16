import SwiftUI

struct NoiseControlHeroStage: View {
    let mode: NoiseControlMode
    let ambientLevel: Int
    let focusOnVoice: Bool
    let isConnected: Bool
    let compact: Bool

    @State private var displayedMode: NoiseControlMode
    @State private var isExpanded = false
    @State private var settleTask: Task<Void, Never>?

    init(
        mode: NoiseControlMode,
        ambientLevel: Int,
        focusOnVoice: Bool,
        isConnected: Bool,
        compact: Bool
    ) {
        self.mode = mode
        self.ambientLevel = ambientLevel
        self.focusOnVoice = focusOnVoice
        self.isConnected = isConnected
        self.compact = compact
        _displayedMode = State(initialValue: mode)
    }

    var body: some View {
        let palette = displayedMode.stagePalette
        let penetration = displayedMode.soundPenetration(ambientLevel: ambientLevel)

        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Acoustic Field")
                            .font(.system(size: compact ? 18 : 20, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(displayedMode.stageDescription)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            metricPills(palette: palette, penetration: penetration)
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            metricPills(palette: palette, penetration: penetration)
                        }
                    }
                }

                GeometryReader { geometry in
                    let progress: CGFloat = isExpanded ? 1 : 0
                    let settledScale: CGFloat = compact ? 0.9 : 0.84
                    let scale = settledScale + ((1 - settledScale) * progress)

                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                            .fill(AppTheme.cardFillSecondary)

                        stageBackdrop(palette: palette)

                        NoiseControlStageScene(
                            mode: displayedMode,
                            ambientLevel: ambientLevel,
                            focusOnVoice: focusOnVoice,
                            palette: palette,
                            progress: progress,
                            compact: compact
                        )
                        .scaleEffect(scale)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
                }
                .frame(height: compact ? 164 : 198)
            }
        }
        .onChange(of: mode) { _, newValue in
            triggerTransition(to: newValue)
        }
        .onDisappear {
            settleTask?.cancel()
        }
    }

    @ViewBuilder
    private func metricPills(palette: NoiseControlStagePalette, penetration: CGFloat) -> some View {
        StageMetricPill(
            label: "Inside",
            value: "\(Int((penetration * 100).rounded()))%",
            tint: palette.primary
        )

        if displayedMode == .ambient && focusOnVoice {
            StageMetricPill(label: "Voice", value: "Focus", tint: palette.highlight)
        }

        StageMetricPill(
            label: isConnected ? "Live" : "Preview",
            value: displayedMode.stageBadge,
            tint: palette.highlight
        )
    }

    @ViewBuilder
    private func stageBackdrop(palette: NoiseControlStagePalette) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        palette.base.opacity(0.34),
                        AppTheme.panelSecondary.opacity(0.96),
                        AppTheme.panel.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(palette.glow.opacity(0.22))
                    .frame(width: width * 0.32, height: width * 0.32)
                    .blur(radius: 42)
                    .offset(x: -width * 0.28, y: -height * 0.12)

                Circle()
                    .fill(palette.primary.opacity(0.12))
                    .frame(width: width * 0.28, height: width * 0.28)
                    .blur(radius: 38)
                    .offset(x: width * 0.26, y: height * 0.08)

                VStack(spacing: height / 4.3) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(AppTheme.divider.opacity(0.42))
                            .frame(height: 1)
                    }
                }

                HStack(spacing: width / 6) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle()
                            .fill(AppTheme.divider.opacity(0.24))
                            .frame(width: 1)
                    }
                }
            }
        }
    }

    private func triggerTransition(to newMode: NoiseControlMode) {
        settleTask?.cancel()
        displayedMode = newMode

        withAnimation(AppTheme.heroStageExpand) {
            isExpanded = true
        }

        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(AppTheme.heroStageSettle) {
                    isExpanded = false
                }
            }
        }
    }
}

private struct NoiseControlStageScene: View {
    let mode: NoiseControlMode
    let ambientLevel: Int
    let focusOnVoice: Bool
    let palette: NoiseControlStagePalette
    let progress: CGFloat
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let metrics = HeadphoneSceneMetrics(
                size: geometry.size,
                compact: compact,
                progress: progress
            )
            let penetration = mode.soundPenetration(ambientLevel: ambientLevel)
            let innerAmplitude = 0.45 + (penetration * 0.65)
            let voiceTightening = focusOnVoice && mode == .ambient ? 0.82 : 1

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    AcousticWaveField(
                        palette: palette,
                        time: time,
                        amplitudeScale: 1 + (progress * 0.18),
                        brightness: 0.9,
                        speed: 1.75
                    )
                    .mask(SoundZoneMask(zone: .outside, metrics: metrics))
                    .opacity(0.38 + (Double(progress) * 0.14))

                    AcousticWaveField(
                        palette: palette,
                        time: time + 0.45,
                        amplitudeScale: innerAmplitude * voiceTightening,
                        brightness: 0.72 + (Double(penetration) * 0.2),
                        speed: 1.35
                    )
                    .mask(SoundZoneMask(zone: .inside, metrics: metrics))
                    .opacity(Double(0.12 + (penetration * 0.74)))

                    if mode == .noiseCancelling {
                        BlockingShield(metrics: metrics, palette: palette, progress: progress)
                    }

                    HeadphoneCenterpiece(
                        metrics: metrics,
                        palette: palette,
                        penetration: penetration,
                        progress: progress
                    )

                    if focusOnVoice && mode == .ambient {
                        VoiceFocusBeacon(metrics: metrics, palette: palette)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

private struct AcousticWaveField: View {
    let palette: NoiseControlStagePalette
    let time: TimeInterval
    let amplitudeScale: CGFloat
    let brightness: Double
    let speed: CGFloat

    var body: some View {
        Canvas { context, size in
            let lanes: [CGFloat] = [0.2, 0.34, 0.48, 0.62, 0.76]

            for (index, lane) in lanes.enumerated() {
                let baseline = size.height * lane
                let amplitude = (6 + (CGFloat(index) * 1.35)) * amplitudeScale
                let frequency = 0.021 + (CGFloat(index) * 0.0034)
                let lineWidth = index == 2 ? 2.2 : 1.4
                let phase = (CGFloat(time) * speed) + (CGFloat(index) * 0.95)

                let primaryPath = wavePath(
                    width: size.width,
                    baseline: baseline,
                    amplitude: amplitude,
                    frequency: frequency,
                    phase: phase
                )
                context.stroke(
                    primaryPath,
                    with: .color(palette.primary.opacity(brightness * (0.26 + (Double(index) * 0.05)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                let highlightPath = wavePath(
                    width: size.width,
                    baseline: baseline + 1.5,
                    amplitude: amplitude * 0.78,
                    frequency: frequency * 1.08,
                    phase: -phase + 1.2
                )
                context.stroke(
                    highlightPath,
                    with: .color(palette.highlight.opacity(brightness * 0.14)),
                    style: StrokeStyle(lineWidth: 0.95, lineCap: .round)
                )
            }
        }
        .blur(radius: 0.25)
    }

    private func wavePath(
        width: CGFloat,
        baseline: CGFloat,
        amplitude: CGFloat,
        frequency: CGFloat,
        phase: CGFloat
    ) -> Path {
        var path = Path()
        let step: CGFloat = 5
        var x: CGFloat = 0

        while x <= width {
            let y = baseline + sin((x * frequency) + phase) * amplitude

            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }

            x += step
        }

        return path
    }
}

private struct SoundZoneMask: View {
    enum Zone {
        case outside
        case inside
    }

    let zone: Zone
    let metrics: HeadphoneSceneMetrics

    var body: some View {
        Canvas { context, size in
            var path = Path()

            switch zone {
            case .outside:
                path.addRect(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: max(metrics.innerRect.minX - 14, 0),
                        height: size.height
                    )
                )
                path.addRect(
                    CGRect(
                        x: min(metrics.innerRect.maxX + 14, size.width),
                        y: 0,
                        width: max(size.width - metrics.innerRect.maxX - 14, 0),
                        height: size.height
                    )
                )
            case .inside:
                let insideRect = metrics.innerRect.insetBy(dx: -10, dy: -8)
                path.addRoundedRect(
                    in: insideRect,
                    cornerSize: CGSize(width: insideRect.height / 2, height: insideRect.height / 2)
                )
            }

            context.fill(path, with: .color(.white))
        }
    }
}

private struct HeadphoneCenterpiece: View {
    let metrics: HeadphoneSceneMetrics
    let palette: NoiseControlStagePalette
    let penetration: CGFloat
    let progress: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.innerRect.height / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.primary.opacity(0.06 + (penetration * 0.18)),
                            palette.highlight.opacity(0.04 + (penetration * 0.12))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: metrics.innerRect.width, height: metrics.innerRect.height)
                .position(x: metrics.innerRect.midX, y: metrics.innerRect.midY)

            Path { path in
                path.addArc(
                    center: CGPoint(x: metrics.bandRect.midX, y: metrics.bandRect.maxY),
                    radius: metrics.bandRect.width / 2,
                    startAngle: .degrees(205),
                    endAngle: .degrees(-25),
                    clockwise: false
                )
            }
            .stroke(
                palette.highlight.opacity(0.9),
                style: StrokeStyle(lineWidth: 5.5 + progress, lineCap: .round)
            )
            .overlay {
                Path { path in
                    path.addArc(
                        center: CGPoint(x: metrics.bandRect.midX, y: metrics.bandRect.maxY),
                        radius: metrics.bandRect.width / 2,
                        startAngle: .degrees(205),
                        endAngle: .degrees(-25),
                        clockwise: false
                    )
                }
                .stroke(
                    palette.primary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .blur(radius: 10)
            }

            Path { path in
                path.move(to: metrics.leftStemTop)
                path.addLine(to: CGPoint(x: metrics.leftCupRect.midX, y: metrics.leftCupRect.minY + 5))
                path.move(to: metrics.rightStemTop)
                path.addLine(to: CGPoint(x: metrics.rightCupRect.midX, y: metrics.rightCupRect.minY + 5))
            }
            .stroke(
                palette.highlight.opacity(0.8),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
            )

            EarcupShell(
                rect: metrics.leftCupRect,
                palette: palette,
                penetration: penetration
            )

            EarcupShell(
                rect: metrics.rightCupRect,
                palette: palette,
                penetration: penetration
            )
        }
    }
}

private struct EarcupShell: View {
    let rect: CGRect
    let palette: NoiseControlStagePalette
    let penetration: CGFloat

    var body: some View {
        let gateOpacity = 0.26 + ((1 - penetration) * 0.4)

        RoundedRectangle(cornerRadius: rect.width * 0.42, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.panel.opacity(0.98),
                        AppTheme.panelSecondary.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: rect.width * 0.42, style: .continuous)
                    .stroke(palette.highlight.opacity(0.42), lineWidth: 1.3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rect.width * 0.33, style: .continuous)
                    .stroke(palette.primary.opacity(0.16 + (gateOpacity * 0.25)), lineWidth: 1)
                    .padding(5)
            )
            .overlay {
                VStack(spacing: 5) {
                    Capsule()
                        .fill(palette.primary.opacity(gateOpacity))
                        .frame(width: rect.width * 0.34, height: 2)
                    Capsule()
                        .fill(palette.primary.opacity(gateOpacity * 0.88))
                        .frame(width: rect.width * 0.42, height: 2)
                    Capsule()
                        .fill(palette.primary.opacity(gateOpacity * 0.74))
                        .frame(width: rect.width * 0.3, height: 2)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: palette.glow.opacity(0.16), radius: 12, y: 4)
    }
}

private struct BlockingShield: View {
    let metrics: HeadphoneSceneMetrics
    let palette: NoiseControlStagePalette
    let progress: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cupHeight * 0.54, style: .continuous)
                .stroke(
                    palette.primary.opacity(0.16 + (Double(progress) * 0.08)),
                    style: StrokeStyle(lineWidth: 1.1, dash: [8, 10])
                )
                .frame(width: metrics.bandRect.width * 1.08, height: metrics.cupHeight * 1.18)
                .position(x: metrics.center.x, y: metrics.center.y + 2)

            RoundedRectangle(cornerRadius: metrics.cupHeight * 0.52, style: .continuous)
                .stroke(palette.highlight.opacity(0.08), lineWidth: 10)
                .frame(width: metrics.bandRect.width * 0.95, height: metrics.cupHeight * 1.02)
                .position(x: metrics.center.x, y: metrics.center.y + 1)
                .blur(radius: 12)
        }
    }
}

private struct VoiceFocusBeacon: View {
    let metrics: HeadphoneSceneMetrics
    let palette: NoiseControlStagePalette

    var body: some View {
        Text("Voice Focus")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.highlight)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(palette.base.opacity(0.7))
            )
            .overlay(
                Capsule()
                    .stroke(palette.highlight.opacity(0.3), lineWidth: 1)
            )
            .position(x: metrics.center.x, y: metrics.bandRect.minY + 6)
    }
}

private struct StageMetricPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AppTheme.controlFill)
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct HeadphoneSceneMetrics {
    let size: CGSize
    let center: CGPoint
    let bandRect: CGRect
    let leftCupRect: CGRect
    let rightCupRect: CGRect
    let innerRect: CGRect
    let leftStemTop: CGPoint
    let rightStemTop: CGPoint
    let cupHeight: CGFloat

    init(size: CGSize, compact: Bool, progress: CGFloat) {
        self.size = size

        let bandWidth = (compact ? 176 : 214) + (progress * 14)
        let bandHeight = bandWidth * 0.48
        let cupWidth = bandWidth * 0.22
        let cupHeight = bandWidth * 0.42
        let innerWidth = bandWidth * 0.38
        let innerHeight = cupHeight * 0.5
        let cupOffset = innerWidth / 2 + cupWidth * 0.72

        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
        self.center = center
        self.cupHeight = cupHeight

        bandRect = CGRect(
            x: center.x - (bandWidth / 2),
            y: center.y - cupHeight - (bandHeight * 0.44),
            width: bandWidth,
            height: bandHeight
        )

        innerRect = CGRect(
            x: center.x - (innerWidth / 2),
            y: center.y - (innerHeight / 2),
            width: innerWidth,
            height: innerHeight
        )

        leftCupRect = CGRect(
            x: center.x - cupOffset - (cupWidth / 2),
            y: center.y - (cupHeight / 2),
            width: cupWidth,
            height: cupHeight
        )

        rightCupRect = CGRect(
            x: center.x + cupOffset - (cupWidth / 2),
            y: center.y - (cupHeight / 2),
            width: cupWidth,
            height: cupHeight
        )

        leftStemTop = CGPoint(x: center.x - (bandWidth * 0.27), y: bandRect.maxY - 2)
        rightStemTop = CGPoint(x: center.x + (bandWidth * 0.27), y: bandRect.maxY - 2)
    }
}

private struct NoiseControlStagePalette {
    let base: Color
    let primary: Color
    let highlight: Color
    let glow: Color
}

private extension NoiseControlMode {
    func soundPenetration(ambientLevel: Int) -> CGFloat {
        switch self {
        case .noiseCancelling:
            return 0.12
        case .ambient:
            let clampedLevel = max(0, min(ambientLevel, 19))
            return 0.42 + (CGFloat(clampedLevel) / 19) * 0.5
        case .off:
            return 0.62
        }
    }

    var stagePalette: NoiseControlStagePalette {
        switch self {
        case .noiseCancelling:
            NoiseControlStagePalette(
                base: AppTheme.accent.opacity(0.3),
                primary: AppTheme.accent,
                highlight: AppTheme.ancHighlight,
                glow: AppTheme.accent.opacity(0.7)
            )
        case .ambient:
            NoiseControlStagePalette(
                base: AppTheme.ambientAccent.opacity(0.28),
                primary: AppTheme.ambientAccent,
                highlight: AppTheme.ambientHighlight,
                glow: AppTheme.ambientAccent.opacity(0.62)
            )
        case .off:
            NoiseControlStagePalette(
                base: AppTheme.offAccent.opacity(0.24),
                primary: AppTheme.offAccent,
                highlight: AppTheme.offHighlight,
                glow: AppTheme.offAccent.opacity(0.5)
            )
        }
    }

    var stageDescription: String {
        switch self {
        case .noiseCancelling:
            "Outside waves stay strong around the cups while only a thin trace leaks into the center."
        case .ambient:
            "Ambient opens the field so more outside sound travels through the headphones into the middle."
        case .off:
            "With control off, a neutral amount of room sound passes through the headphones."
        }
    }

    var stageBadge: String {
        switch self {
        case .noiseCancelling:
            "ANC"
        case .ambient:
            "AMB"
        case .off:
            "OFF"
        }
    }
}
