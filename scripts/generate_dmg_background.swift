import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: swift generate_dmg_background.swift /output/path/background.png\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 880, height: 560)

enum Palette {
    static let graphite = NSColor(hex: 0x0B0B0D)
    static let graphiteSoft = NSColor(hex: 0x14161A)
    static let graphiteSurface = NSColor(hex: 0x1A1D22)
    static let ivory = NSColor(hex: 0xF5F0E6)
    static let champagne = NSColor(hex: 0xE3C98A)
    static let champagneDeep = NSColor(hex: 0xA67B33)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let context = graphicsContext.cgContext
let canvasRect = CGRect(origin: .zero, size: size)

drawLinearGradient(
    in: canvasRect,
    colors: [Palette.graphiteSoft, Palette.graphite],
    angle: -20
)

drawRadialGlow(
    in: context,
    center: CGPoint(x: 740, y: 96),
    startRadius: 20,
    endRadius: 330,
    color: Palette.champagne.withAlphaComponent(0.28)
)

drawRadialGlow(
    in: context,
    center: CGPoint(x: 130, y: 484),
    startRadius: 12,
    endRadius: 250,
    color: Palette.ivory.withAlphaComponent(0.16)
)

for offset in stride(from: 0.0, through: 160.0, by: 42.0) {
    let wave = NSBezierPath()
    wave.lineWidth = offset == 0 ? 14 : 8
    wave.lineCapStyle = .butt
    wave.move(to: CGPoint(x: 552 + offset, y: 64))
    wave.curve(
        to: CGPoint(x: 744 + offset * 0.18, y: 506),
        controlPoint1: CGPoint(x: 658 + offset * 0.92, y: 208),
        controlPoint2: CGPoint(x: 686 + offset * 0.32, y: 404)
    )
    Palette.champagne.withAlphaComponent(offset == 0 ? 0.09 : 0.045).setStroke()
    wave.stroke()
}

drawSpotlight(at: CGPoint(x: 214, y: 250))
drawSpotlight(at: CGPoint(x: 664, y: 250))
drawConnector()
drawTitles()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode DMG background image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)

func drawTitles() {
    drawText(
        "Install Sony Audio",
        rect: CGRect(x: 64, y: 442, width: 420, height: 48),
        font: .systemFont(ofSize: 34, weight: .semibold),
        color: Palette.ivory
    )

    drawText(
        "Drag the app into Applications",
        rect: CGRect(x: 66, y: 400, width: 420, height: 28),
        font: .systemFont(ofSize: 18, weight: .medium),
        color: Palette.champagne
    )

    drawText(
        "Native Sony headphone controls with the app's graphite and champagne look.",
        rect: CGRect(x: 66, y: 350, width: 470, height: 44),
        font: .systemFont(ofSize: 13, weight: .regular),
        color: Palette.ivory.withAlphaComponent(0.62)
    )
}

func drawSpotlight(at center: CGPoint) {
    let plateRect = CGRect(x: center.x - 88, y: center.y - 88, width: 176, height: 176)
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: 44, yRadius: 44)

    drawRadialGlow(
        in: context,
        center: CGPoint(x: center.x, y: center.y + 10),
        startRadius: 4,
        endRadius: 144,
        color: Palette.ivory.withAlphaComponent(0.09)
    )

    context.saveGState()
    platePath.addClip()
    drawLinearGradient(
        in: plateRect,
        colors: [
            Palette.graphiteSurface.withAlphaComponent(0.74),
            Palette.graphite.withAlphaComponent(0.58)
        ],
        angle: -90
    )
    drawLinearGradient(
        in: CGRect(x: plateRect.minX, y: plateRect.midY, width: plateRect.width, height: plateRect.height / 2),
        colors: [
            Palette.ivory.withAlphaComponent(0.08),
            NSColor.clear
        ],
        angle: -90
    )
    context.restoreGState()

    platePath.lineWidth = 2
    Palette.ivory.withAlphaComponent(0.13).setStroke()
    platePath.stroke()

    let halo = NSBezierPath(ovalIn: CGRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128))
    halo.lineWidth = 4
    Palette.champagne.withAlphaComponent(0.22).setStroke()
    halo.stroke()
}

func drawConnector() {
    let connectorRect = CGRect(x: 332, y: 246, width: 216, height: 10)
    let connectorPath = NSBezierPath(roundedRect: connectorRect, xRadius: 5, yRadius: 5)
    context.saveGState()
    connectorPath.addClip()
    drawLinearGradient(
        in: connectorRect,
        colors: [
            Palette.champagne.withAlphaComponent(0.0),
            Palette.champagne.withAlphaComponent(0.92),
            Palette.champagne.withAlphaComponent(0.0)
        ],
        angle: 0
    )
    context.restoreGState()

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 548, y: 228))
    arrow.line(to: CGPoint(x: 588, y: 250))
    arrow.line(to: CGPoint(x: 548, y: 272))
    arrow.close()
    Palette.champagne.withAlphaComponent(0.94).setFill()
    arrow.fill()
}

func drawText(_ string: String, rect: CGRect, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    NSString(string: string).draw(in: rect, withAttributes: attributes)
}

func drawLinearGradient(in rect: CGRect, colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: rect, angle: angle)
}

func drawRadialGlow(in context: CGContext, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, color: NSColor) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0.0, 1.0]
    ) else {
        return
    }

    context.saveGState()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: startRadius,
        endCenter: center,
        endRadius: endRadius,
        options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
    )
    context.restoreGState()
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
