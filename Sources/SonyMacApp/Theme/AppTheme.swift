import AppKit
import SwiftUI

enum AppTheme {
    static let backgroundBase = Color(light: 0xF5F0E6, dark: 0x0B0B0D)
    static let panel = Color(light: 0xFFFDF8, dark: 0x141418)
    static let panelSecondary = Color(light: 0xF3ECE1, dark: 0x101014)
    static let divider = Color(light: 0x151313, dark: 0xFFFFFF, lightAlpha: 0.1, darkAlpha: 0.06)

    static let textPrimary = Color(light: 0x151316, dark: 0xEAEAEA)
    static let textSecondary = Color(light: 0x6E6459, dark: 0x8A8A8A)
    static let textMuted = Color(light: 0x95897A, dark: 0x6E6E6E)

    static let accent = Color(light: 0xA67B33, dark: 0xE3C98A)
    static let accentMuted = Color(light: 0x8C6D3F, dark: 0xBFA86F)
    static let ancHighlight = Color(light: 0xCFA35F, dark: 0xF1DCAA)
    static let ambientAccent = Color(light: 0x4E938C, dark: 0x8FD3CB)
    static let ambientHighlight = Color(light: 0x72AFA8, dark: 0xB5F1E7)
    static let offAccent = Color(light: 0x7D746A, dark: 0x6F7683)
    static let offHighlight = Color(light: 0xA59C93, dark: 0xA0A9BA)
    static let disabled = Color(light: 0xCBC0B1, dark: 0x3A3A3A)

    static let shadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.45)

    static var background: some View {
        ZStack {
            backgroundBase

            LinearGradient(
                colors: [
                    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.015),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accent.opacity(0.08),
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

    static let controlFill = Color(light: 0xECE3D6, dark: 0x1A1A1E)
    static let controlStroke = Color(light: 0x151313, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.05)
    static let controlFillActive = accent
    static let sliderTrack = Color(light: 0xD8CCBD, dark: 0x2A2A2E)
    static let toggleOff = Color(light: 0xD7CCBF, dark: 0x2A2A2E)

    static let detailFill = Color(light: 0xF7F0E4, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.16)
    static let detailFillSecondary = Color(light: 0xF2E7D8, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.14)

    static let switchThumb = Color(hex: 0xFFFFFF)
    static let switchThumbShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.1, darkAlpha: 0.22)

    static let splashWordmark = Color(light: 0x1D1712, dark: 0xFFFFFF)
    static let splashGlow = Color(light: 0xA67B33, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.05)
    static let splashDivider = Color(light: 0xA67B33, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.18)
    static let heroStageShell = Color(light: 0xE7DCCB, dark: 0x272C34)
    static let heroStageShellSecondary = Color(light: 0xD3C6B4, dark: 0x333944)
    static let heroStagePad = Color(light: 0xF7F0E4, dark: 0x11141A)
    static let heroStagePadInner = Color(light: 0xD8CAB8, dark: 0x06080C)
    static let heroStageSheen = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.34, darkAlpha: 0.06)
    static let heroStageDivider = Color(light: 0xA67B33, dark: 0xFFFFFF, lightAlpha: 0.18, darkAlpha: 0.08)
    static let heroStageSummaryFill = Color(light: 0xFBF4EA, dark: 0x0F1217, lightAlpha: 0.84, darkAlpha: 0.82)

    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 999
    static let panelPadding: CGFloat = 20
    static let sectionPadding: CGFloat = 24
    static let elementSpacing: CGFloat = 12
    static let largeSectionSpacing: CGFloat = 32
    static let standardAnimation = Animation.easeInOut(duration: 0.2)
    static let heroStageExpand = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let heroStageSettle = Animation.spring(response: 0.8, dampingFraction: 0.88)
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.isDarkMode
                    ? NSColor(hex: dark, alpha: darkAlpha)
                    : NSColor(hex: light, alpha: lightAlpha)
            }
        )
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        switch bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
        case .darkAqua, .vibrantDark:
            return true
        default:
            return false
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
