import SwiftUI

private let showsConnectionRecoveryDialog = false

struct ContentView: View {
    @Bindable var session: SonyHeadphoneSession
    @Bindable var launchAtLogin: LaunchAtLoginController
    @State private var showSplash = true
    @State private var contentOpacity = 0.0
    @State private var startupTaskStarted = false

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 1040

            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    MonolithControlSurface(session: session, launchAtLogin: launchAtLogin, compact: isCompact)
                        .frame(maxWidth: isCompact ? .infinity : 980, alignment: .top)
                        .padding(AppTheme.sectionPadding)
                        .animation(AppTheme.standardAnimation, value: isCompact)
                }
                .opacity(contentOpacity)

                if showSplash {
                    StartupSplashView()
                        .transition(.opacity)
                        .zIndex(5)
                }

                if showsConnectionRecoveryDialog, let guide = session.connectionRecoveryGuide {
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
