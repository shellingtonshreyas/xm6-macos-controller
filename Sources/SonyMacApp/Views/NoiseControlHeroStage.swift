import SwiftUI

private let heroStageLiveAnimationEnabled = false

struct NoiseControlHeroStage: View {
    let mode: NoiseControlMode
    let ambientLevel: Int
    let focusOnVoice: Bool
    let isConnected: Bool
    let compact: Bool
    let connectionLabel: String
    let transportSummary: String
    let modeChipLabel: String
    let ambientChipLabel: String
    let dseeChipLabel: String

    @State private var displayedMode: NoiseControlMode
    @State private var isExpanded = false
    @State private var settleTask: Task<Void, Never>?

    init(
        mode: NoiseControlMode,
        ambientLevel: Int,
        focusOnVoice: Bool,
        isConnected: Bool,
        compact: Bool,
        connectionLabel: String,
        transportSummary: String,
        modeChipLabel: String,
        ambientChipLabel: String,
        dseeChipLabel: String
    ) {
        self.mode = mode
        self.ambientLevel = ambientLevel
        self.focusOnVoice = focusOnVoice
        self.isConnected = isConnected
        self.compact = compact
        self.connectionLabel = connectionLabel
        self.transportSummary = transportSummary
        self.modeChipLabel = modeChipLabel
        self.ambientChipLabel = ambientChipLabel
        self.dseeChipLabel = dseeChipLabel
        _displayedMode = State(initialValue: mode)
    }

    private var sceneHorizontalInset: CGFloat {
        compact ? 22 : 30
    }

    private var sceneHeight: CGFloat {
        compact ? 186 : 228
    }

    private var summary: AcousticHeroSummary {
        let palette = displayedMode.stagePalette

        return AcousticHeroSummary(
            connectionLabel: connectionLabel,
            transportSummary: transportSummary,
            chips: [
                AcousticHeroChip(title: modeChipLabel, tint: palette.primary),
                AcousticHeroChip(
                    title: ambientChipLabel,
                    tint: focusOnVoice && displayedMode == .ambient ? palette.highlight : AppTheme.accentMuted
                ),
                AcousticHeroChip(title: dseeChipLabel, tint: AppTheme.textPrimary, highlighted: false)
            ]
        )
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

                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        let progress: CGFloat = isExpanded ? 1 : 0
                        let settledScale: CGFloat = compact ? 0.94 : 0.89
                        let scale = settledScale + ((1 - settledScale) * progress)

                        NoiseControlStageScene(
                            mode: displayedMode,
                            ambientLevel: ambientLevel,
                            focusOnVoice: focusOnVoice,
                            palette: palette,
                            progress: progress,
                            compact: compact,
                            horizontalInset: sceneHorizontalInset
                        )
                        .scaleEffect(scale)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(height: sceneHeight)

                    AcousticHeroSummaryBand(
                        summary: summary,
                        compact: compact,
                        horizontalInset: sceneHorizontalInset,
                        palette: palette
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                        .fill(AppTheme.cardFillSecondary)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [
                                    AppTheme.heroStageSheen.opacity(0.22),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
                        }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
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

    private func triggerTransition(to newMode: NoiseControlMode) {
        settleTask?.cancel()
        displayedMode = newMode

        if heroStageLiveAnimationEnabled {
            withAnimation(AppTheme.heroStageExpand) {
                isExpanded = true
            }
        } else {
            isExpanded = false
        }

        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if heroStageLiveAnimationEnabled {
                    withAnimation(AppTheme.heroStageSettle) {
                        isExpanded = false
                    }
                } else {
                    isExpanded = false
                }
            }
        }
    }
}

private struct AcousticHeroSummaryBand: View {
    let summary: AcousticHeroSummary
    let compact: Bool
    let horizontalInset: CGFloat
    let palette: NoiseControlStagePalette

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    AppTheme.heroStageSummaryFill.opacity(0.0),
                    AppTheme.heroStageSummaryFill.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppTheme.heroStageDivider.opacity(0.8),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [
                                palette.primary.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                    }

                if compact {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryCopy
                        chipRow
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 16)
                } else {
                    HStack(alignment: .center, spacing: 24) {
                        summaryCopy
                        Spacer(minLength: 20)
                        chipRow
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private var summaryCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(summary.connectionLabel)
                .font(.system(size: compact ? 24 : 30, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.transportSummary)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chipRow: some View {
        ViewThatFits(in: compact ? .vertical : .horizontal) {
            HStack(spacing: 10) {
                ForEach(summary.chips) { chip in
                    HeroSummaryChip(chip: chip)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary.chips) { chip in
                    HeroSummaryChip(chip: chip)
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
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let metrics = HeadphoneSceneMetrics(
                size: geometry.size,
                compact: compact,
                progress: progress,
                horizontalInset: horizontalInset
            )
            let penetration = mode.soundPenetration(ambientLevel: ambientLevel)
            let innerAmplitude = 0.45 + (penetration * 0.65)
            let voiceTightening = focusOnVoice && mode == .ambient ? 0.82 : 1

            if heroStageLiveAnimationEnabled {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    stageScene(
                        metrics: metrics,
                        penetration: penetration,
                        innerAmplitude: innerAmplitude,
                        voiceTightening: voiceTightening,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                stageScene(
                    metrics: metrics,
                    penetration: penetration,
                    innerAmplitude: innerAmplitude,
                    voiceTightening: voiceTightening,
                    time: 0
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    @ViewBuilder
    private func stageScene(
        metrics: HeadphoneSceneMetrics,
        penetration: CGFloat,
        innerAmplitude: CGFloat,
        voiceTightening: CGFloat,
        time: TimeInterval
    ) -> some View {
        ZStack {
            StageBackdrop(metrics: metrics, palette: palette)

            AcousticWaveField(
                rect: metrics.stageRect,
                palette: palette,
                time: time,
                amplitudeScale: 1 + (progress * 0.18),
                brightness: 0.9,
                speed: 1.75
            )
            .mask(SoundZoneMask(zone: .outside, metrics: metrics))
            .opacity(0.38 + (Double(progress) * 0.14))

            AcousticWaveField(
                rect: metrics.stageRect,
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
    }
}

private struct StageBackdrop: View {
    let metrics: HeadphoneSceneMetrics
    let palette: NoiseControlStagePalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: min(metrics.stageRect.height * 0.18, 24), style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.base.opacity(0.24),
                            AppTheme.panelSecondary.opacity(0.98),
                            AppTheme.panel.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: metrics.stageRect.width, height: metrics.stageRect.height)
                .position(x: metrics.stageRect.midX, y: metrics.stageRect.midY)

            Circle()
                .fill(palette.glow.opacity(0.16))
                .frame(width: metrics.stageRect.width * 0.38, height: metrics.stageRect.width * 0.38)
                .blur(radius: 34)
                .position(
                    x: metrics.stageRect.minX + (metrics.stageRect.width * 0.22),
                    y: metrics.stageRect.minY + (metrics.stageRect.height * 0.3)
                )

            Circle()
                .fill(palette.primary.opacity(0.12))
                .frame(width: metrics.stageRect.width * 0.3, height: metrics.stageRect.width * 0.3)
                .blur(radius: 30)
                .position(
                    x: metrics.stageRect.maxX - (metrics.stageRect.width * 0.18),
                    y: metrics.stageRect.maxY - (metrics.stageRect.height * 0.26)
                )

            VStack(spacing: metrics.stageRect.height / 4.1) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(AppTheme.divider.opacity(0.32))
                        .frame(height: 1)
                }
            }
            .frame(
                width: metrics.stageRect.width * 0.98,
                height: metrics.stageRect.height * 0.84
            )
            .position(x: metrics.stageRect.midX, y: metrics.stageRect.midY)

            HStack(spacing: metrics.stageRect.width / 5.2) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(AppTheme.divider.opacity(0.18))
                        .frame(width: 1)
                }
            }
            .frame(
                width: metrics.stageRect.width * 0.92,
                height: metrics.stageRect.height
            )
            .position(x: metrics.stageRect.midX, y: metrics.stageRect.midY)

            LinearGradient(
                colors: [
                    AppTheme.panel.opacity(0.44),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: metrics.stageRect.width * 0.12, height: metrics.stageRect.height)
            .position(
                x: metrics.stageRect.minX + (metrics.stageRect.width * 0.06),
                y: metrics.stageRect.midY
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    AppTheme.panel.opacity(0.42)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: metrics.stageRect.width * 0.12, height: metrics.stageRect.height)
            .position(
                x: metrics.stageRect.maxX - (metrics.stageRect.width * 0.06),
                y: metrics.stageRect.midY
            )
        }
    }
}

private struct AcousticWaveField: View {
    let rect: CGRect
    let palette: NoiseControlStagePalette
    let time: TimeInterval
    let amplitudeScale: CGFloat
    let brightness: Double
    let speed: CGFloat

    var body: some View {
        Canvas { context, _ in
            let lanes: [CGFloat] = [0.18, 0.32, 0.46, 0.6, 0.74]

            for (index, lane) in lanes.enumerated() {
                let baseline = rect.minY + (rect.height * lane)
                let amplitude = (6 + (CGFloat(index) * 1.35)) * amplitudeScale
                let frequency = 0.021 + (CGFloat(index) * 0.0034)
                let lineWidth = index == 2 ? 2.2 : 1.4
                let phase = (CGFloat(time) * speed) + (CGFloat(index) * 0.95)

                let primaryPath = wavePath(
                    rect: rect,
                    baseline: baseline,
                    amplitude: amplitude,
                    frequency: frequency,
                    phase: phase
                )
                context.stroke(
                    primaryPath,
                    with: .color(palette.primary.opacity(brightness * (0.24 + (Double(index) * 0.05)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                let highlightPath = wavePath(
                    rect: rect,
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
        rect: CGRect,
        baseline: CGFloat,
        amplitude: CGFloat,
        frequency: CGFloat,
        phase: CGFloat
    ) -> Path {
        var path = Path()
        let step: CGFloat = 5
        var x = rect.minX

        while x <= rect.maxX {
            let localX = x - rect.minX
            let y = baseline + sin((localX * frequency) + phase) * amplitude

            if x == rect.minX {
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
        Canvas { context, _ in
            var path = Path()

            switch zone {
            case .outside:
                path.addRect(
                    CGRect(
                        x: metrics.stageRect.minX,
                        y: metrics.stageRect.minY,
                        width: max(metrics.innerRect.minX - metrics.stageRect.minX - 18, 0),
                        height: metrics.stageRect.height
                    )
                )
                path.addRect(
                    CGRect(
                        x: metrics.innerRect.maxX + 18,
                        y: metrics.stageRect.minY,
                        width: max(metrics.stageRect.maxX - metrics.innerRect.maxX - 18, 0),
                        height: metrics.stageRect.height
                    )
                )
            case .inside:
                let insideRect = metrics.innerRect.insetBy(dx: -14, dy: -10)
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
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.primary.opacity(0.12 + (penetration * 0.16)),
                            palette.highlight.opacity(0.1 + (penetration * 0.12))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(
                    width: metrics.innerRect.width * (1.06 + (penetration * 0.18)),
                    height: metrics.innerRect.height * 0.92
                )
                .blur(radius: 12)
                .position(x: metrics.innerRect.midX, y: metrics.innerRect.midY)

            Capsule()
                .fill(AppTheme.heroStageSheen.opacity(0.08))
                .frame(
                    width: metrics.innerRect.width * 0.72,
                    height: metrics.innerRect.height * 0.42
                )
                .position(x: metrics.innerRect.midX, y: metrics.innerRect.midY)

            bandPath
                .stroke(
                    Color.black.opacity(0.28),
                    style: StrokeStyle(lineWidth: metrics.bandThickness + 10, lineCap: .round)
                )
                .blur(radius: 12)

            bandPath
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.heroStageShellSecondary,
                            AppTheme.heroStageShell
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: metrics.bandThickness, lineCap: .round)
                )

            bandPath
                .stroke(
                    palette.highlight.opacity(0.84),
                    style: StrokeStyle(lineWidth: max(metrics.bandThickness * 0.2, 4), lineCap: .round)
                )

            bandPath
                .stroke(
                    AppTheme.heroStageSheen.opacity(0.16),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .offset(y: -3)

            yokePath(side: .left)
                .stroke(
                    AppTheme.heroStageShellSecondary,
                    style: StrokeStyle(lineWidth: metrics.bandThickness * 0.34, lineCap: .round, lineJoin: .round)
                )

            yokePath(side: .left)
                .stroke(
                    palette.highlight.opacity(0.34),
                    style: StrokeStyle(lineWidth: max(metrics.bandThickness * 0.1, 2), lineCap: .round)
                )

            yokePath(side: .right)
                .stroke(
                    AppTheme.heroStageShellSecondary,
                    style: StrokeStyle(lineWidth: metrics.bandThickness * 0.34, lineCap: .round, lineJoin: .round)
                )

            yokePath(side: .right)
                .stroke(
                    palette.highlight.opacity(0.34),
                    style: StrokeStyle(lineWidth: max(metrics.bandThickness * 0.1, 2), lineCap: .round)
                )

            hinge(side: .left)
            hinge(side: .right)

            XM6Earcup(
                rect: metrics.leftCupRect,
                palette: palette,
                penetration: penetration,
                side: .left
            )

            XM6Earcup(
                rect: metrics.rightCupRect,
                palette: palette,
                penetration: penetration,
                side: .right
            )
        }
    }

    private var bandPath: Path {
        Path { path in
            path.addArc(
                center: CGPoint(x: metrics.bandRect.midX, y: metrics.bandRect.maxY + 2),
                radius: metrics.bandRect.width / 2,
                startAngle: .degrees(206),
                endAngle: .degrees(-26),
                clockwise: false
            )
        }
    }

    private func yokePath(side: HeadphoneSide) -> Path {
        let stemTop = side == .left ? metrics.leftStemTop : metrics.rightStemTop
        let cupAnchor = side == .left ? metrics.leftCupAnchor : metrics.rightCupAnchor
        let widthDirection: CGFloat = side == .left ? -1 : 1

        return Path { path in
            path.move(to: stemTop)
            path.addCurve(
                to: cupAnchor,
                control1: CGPoint(
                    x: stemTop.x + (metrics.bandRect.width * 0.06 * widthDirection),
                    y: stemTop.y + (metrics.cupHeight * 0.2)
                ),
                control2: CGPoint(
                    x: cupAnchor.x + (metrics.leftCupRect.width * 0.12 * widthDirection),
                    y: cupAnchor.y - (metrics.cupHeight * 0.16)
                )
            )
        }
    }

    @ViewBuilder
    private func hinge(side: HeadphoneSide) -> some View {
        let rect = side == .left ? metrics.leftHingeRect : metrics.rightHingeRect

        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.heroStageShellSecondary,
                        AppTheme.heroStageShell
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(palette.highlight.opacity(0.26), lineWidth: 1)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

private struct XM6Earcup: View {
    let rect: CGRect
    let palette: NoiseControlStagePalette
    let penetration: CGFloat
    let side: HeadphoneSide

    var body: some View {
        let shellRadius = rect.width * 0.44
        let innerPadding = rect.width * 0.14
        let slitOpacity = 0.3 + ((1 - penetration) * 0.18)

        ZStack {
            RoundedRectangle(cornerRadius: shellRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.heroStageShellSecondary.opacity(0.98),
                            AppTheme.heroStageShell.opacity(0.96),
                            AppTheme.heroStagePadInner.opacity(0.84)
                        ],
                        startPoint: side == .left ? .topLeading : .topTrailing,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: shellRadius, style: .continuous)
                        .stroke(palette.highlight.opacity(0.26), lineWidth: 1.4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rect.width * 0.35, style: .continuous)
                        .stroke(AppTheme.heroStageSheen.opacity(0.12), lineWidth: 1)
                        .padding(5)
                )

            RoundedRectangle(cornerRadius: rect.width * 0.34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.heroStagePad,
                            AppTheme.heroStagePadInner
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(innerPadding)
                .overlay(
                    RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous)
                        .stroke(AppTheme.heroStageSheen.opacity(0.08), lineWidth: 1)
                        .padding(innerPadding + 5)
                )

            VStack(spacing: rect.height * 0.055) {
                Capsule()
                    .fill(palette.primary.opacity(slitOpacity))
                    .frame(width: rect.width * 0.32, height: 2.6)
                Capsule()
                    .fill(palette.primary.opacity(slitOpacity * 0.86))
                    .frame(width: rect.width * 0.42, height: 2.6)
                Capsule()
                    .fill(palette.primary.opacity(slitOpacity * 0.72))
                    .frame(width: rect.width * 0.26, height: 2.6)
            }

            Capsule()
                .fill(AppTheme.heroStageSheen.opacity(0.06))
                .frame(width: rect.width * 0.16, height: rect.height * 0.58)
                .offset(x: side == .left ? -rect.width * 0.18 : rect.width * 0.18)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: palette.glow.opacity(0.14), radius: 14, y: 8)
    }
}

private struct BlockingShield: View {
    let metrics: HeadphoneSceneMetrics
    let palette: NoiseControlStagePalette
    let progress: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cupHeight * 0.56, style: .continuous)
                .stroke(
                    palette.primary.opacity(0.16 + (Double(progress) * 0.08)),
                    style: StrokeStyle(lineWidth: 1.1, dash: [8, 10])
                )
                .frame(width: metrics.bandRect.width * 1.1, height: metrics.cupHeight * 1.22)
                .position(x: metrics.center.x, y: metrics.center.y + 4)

            RoundedRectangle(cornerRadius: metrics.cupHeight * 0.54, style: .continuous)
                .stroke(palette.highlight.opacity(0.08), lineWidth: 10)
                .frame(width: metrics.bandRect.width * 0.96, height: metrics.cupHeight * 1.06)
                .position(x: metrics.center.x, y: metrics.center.y + 3)
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
                    .fill(AppTheme.panel.opacity(0.78))
            )
            .overlay(
                Capsule()
                    .stroke(palette.highlight.opacity(0.28), lineWidth: 1)
            )
            .position(x: metrics.center.x, y: metrics.stageRect.minY + 14)
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

private struct HeroSummaryChip: View {
    let chip: AcousticHeroChip

    var body: some View {
        Text(chip.title)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(chip.highlighted ? AppTheme.controlFill : AppTheme.cardFill.opacity(0.58))
            )
            .foregroundStyle(chip.tint)
            .overlay(
                Capsule()
                    .stroke(
                        chip.highlighted ? chip.tint.opacity(0.28) : AppTheme.controlStroke,
                        lineWidth: 1
                    )
            )
    }
}

private struct HeadphoneSceneMetrics {
    let size: CGSize
    let stageRect: CGRect
    let center: CGPoint
    let bandRect: CGRect
    let leftCupRect: CGRect
    let rightCupRect: CGRect
    let innerRect: CGRect
    let leftStemTop: CGPoint
    let rightStemTop: CGPoint
    let leftCupAnchor: CGPoint
    let rightCupAnchor: CGPoint
    let leftHingeRect: CGRect
    let rightHingeRect: CGRect
    let cupHeight: CGFloat
    let bandThickness: CGFloat

    init(size: CGSize, compact: Bool, progress: CGFloat, horizontalInset: CGFloat) {
        self.size = size

        stageRect = CGRect(
            x: horizontalInset,
            y: compact ? 10 : 12,
            width: max(size.width - (horizontalInset * 2), 0),
            height: max(size.height - (compact ? 18 : 20), 0)
        )

        let bandWidth = min(stageRect.width * 0.33, compact ? 214 : 270) + (progress * 12)
        let cupWidth = bandWidth * 0.28
        let cupHeight = bandWidth * 0.53
        let innerWidth = bandWidth * 0.48
        let innerHeight = cupHeight * 0.56
        let cupOffset = (innerWidth / 2) + (cupWidth * 0.88)
        let bandThickness = compact ? 24 + (progress * 3) : 30 + (progress * 4)
        let center = CGPoint(
            x: stageRect.midX,
            y: stageRect.midY + (stageRect.height * 0.04)
        )

        self.center = center
        self.cupHeight = cupHeight
        self.bandThickness = bandThickness

        bandRect = CGRect(
            x: center.x - (bandWidth / 2),
            y: center.y - cupHeight - (bandWidth * 0.18),
            width: bandWidth,
            height: bandWidth * 0.6
        )

        innerRect = CGRect(
            x: center.x - (innerWidth / 2),
            y: center.y - (innerHeight / 2) + 2,
            width: innerWidth,
            height: innerHeight
        )

        leftCupRect = CGRect(
            x: center.x - cupOffset - (cupWidth / 2),
            y: center.y - (cupHeight / 2) + 8,
            width: cupWidth,
            height: cupHeight
        )

        rightCupRect = CGRect(
            x: center.x + cupOffset - (cupWidth / 2),
            y: center.y - (cupHeight / 2) + 8,
            width: cupWidth,
            height: cupHeight
        )

        leftStemTop = CGPoint(
            x: center.x - (bandWidth * 0.275),
            y: bandRect.maxY - (bandThickness * 0.34)
        )
        rightStemTop = CGPoint(
            x: center.x + (bandWidth * 0.275),
            y: bandRect.maxY - (bandThickness * 0.34)
        )

        leftCupAnchor = CGPoint(
            x: leftCupRect.midX - (cupWidth * 0.12),
            y: leftCupRect.minY + (cupHeight * 0.16)
        )
        rightCupAnchor = CGPoint(
            x: rightCupRect.midX + (cupWidth * 0.12),
            y: rightCupRect.minY + (cupHeight * 0.16)
        )

        let hingeWidth = cupWidth * 0.18
        let hingeHeight = cupHeight * 0.18

        leftHingeRect = CGRect(
            x: leftCupAnchor.x - (hingeWidth / 2),
            y: leftCupRect.minY + (cupHeight * 0.05),
            width: hingeWidth,
            height: hingeHeight
        )
        rightHingeRect = CGRect(
            x: rightCupAnchor.x - (hingeWidth / 2),
            y: rightCupRect.minY + (cupHeight * 0.05),
            width: hingeWidth,
            height: hingeHeight
        )
    }
}

private struct NoiseControlStagePalette {
    let base: Color
    let primary: Color
    let highlight: Color
    let glow: Color
}

private struct AcousticHeroSummary {
    let connectionLabel: String
    let transportSummary: String
    let chips: [AcousticHeroChip]
}

private struct AcousticHeroChip: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let highlighted: Bool

    init(title: String, tint: Color, highlighted: Bool = true) {
        id = title
        self.title = title
        self.tint = tint
        self.highlighted = highlighted
    }
}

private enum HeadphoneSide {
    case left
    case right
}

private extension NoiseControlMode {
    func soundPenetration(ambientLevel: Int) -> CGFloat {
        switch self {
        case .noiseCancelling:
            return 0.12
        case .ambient:
            let lowerBound = NoiseControlMode.ambientLevelRange.lowerBound
            let upperBound = NoiseControlMode.ambientLevelRange.upperBound
            let clampedLevel = max(lowerBound, min(ambientLevel, upperBound))
            let span = max(upperBound - lowerBound, 1)
            return 0.42 + (CGFloat(clampedLevel - lowerBound) / CGFloat(span)) * 0.5
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
