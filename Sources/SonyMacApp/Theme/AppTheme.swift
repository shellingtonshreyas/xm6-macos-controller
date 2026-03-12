import SwiftUI

enum AppTheme {
    static let backgroundBase = Color(hex: 0x0B0B0D)
    static let panel = Color(hex: 0x141418)
    static let panelSecondary = Color(hex: 0x101014)
    static let divider = Color.white.opacity(0.06)

    static let textPrimary = Color(hex: 0xEAEAEA)
    static let textSecondary = Color(hex: 0x8A8A8A)
    static let textMuted = Color(hex: 0x6E6E6E)

    static let accent = Color(hex: 0xE3C98A)
    static let accentMuted = Color(hex: 0xBFA86F)
    static let disabled = Color(hex: 0x3A3A3A)

    static let shadow = Color.black.opacity(0.45)

    @MainActor
    static var background: some View {
        ZStack {
        backgroundBase
        LinearGradient(
            colors: [
                Color.white.opacity(0.015),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        RadialGradient(
            colors: [
                accent.opacity(0.045),
                Color.clear
            ],
            center: .bottomTrailing,
            startRadius: 20,
            endRadius: 520
        )
    }
    }

    static let cardFill = panel
    static let cardFillSecondary = panelSecondary
    static let cardStroke = divider.opacity(0.9)

    static let controlFill = Color(hex: 0x1A1A1E)
    static let controlStroke = Color.white.opacity(0.05)
    static let controlFillActive = accent
    static let sliderTrack = Color(hex: 0x2A2A2E)
    static let toggleOff = Color(hex: 0x2A2A2E)

    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 999
    static let panelPadding: CGFloat = 20
    static let sectionPadding: CGFloat = 24
    static let elementSpacing: CGFloat = 12
    static let largeSectionSpacing: CGFloat = 32
    static let standardAnimation = Animation.easeInOut(duration: 0.2)
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
