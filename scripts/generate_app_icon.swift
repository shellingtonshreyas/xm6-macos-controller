import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: swift generate_app_icon.swift /output/path/icon.png\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)
let iconRect = CGRect(x: 52, y: 52, width: 920, height: 920)

enum Palette {
    static let graphite = NSColor(hex: 0x0B0B0D)
    static let graphiteHighlight = NSColor(hex: 0x17191D)
    static let graphiteSurface = NSColor(hex: 0x20242A)
    static let graphiteSurfaceSoft = NSColor(hex: 0x2A3037)
    static let ivory = NSColor(hex: 0xF5F0E6)
    static let champagne = NSColor(hex: 0xE3C98A)
    static let champagneDeep = NSColor(hex: 0xB28A43)
    static let shadow = NSColor.black.withAlphaComponent(0.28)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
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
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

drawOuterShadow(in: context, rect: iconRect)
let maskPath = NSBezierPath(roundedRect: iconRect, xRadius: 214, yRadius: 214)

context.saveGState()
maskPath.addClip()

drawLinearGradient(
    in: iconRect,
    colors: [
        Palette.graphiteHighlight,
        NSColor(hex: 0x101216),
        Palette.graphite
    ],
    angle: -52
)

drawRadialGlow(
    in: context,
    center: CGPoint(x: iconRect.maxX - 168, y: iconRect.minY + 164),
    startRadius: 12,
    endRadius: 440,
    color: Palette.champagne.withAlphaComponent(0.42)
)

drawRadialGlow(
    in: context,
    center: CGPoint(x: iconRect.minX + 156, y: iconRect.maxY - 126),
    startRadius: 24,
    endRadius: 360,
    color: Palette.ivory.withAlphaComponent(0.18)
)

let sheenRect = iconRect.insetBy(dx: 36, dy: 32)
drawLinearGradient(
    in: sheenRect,
    colors: [
        Palette.ivory.withAlphaComponent(0.22),
        Palette.ivory.withAlphaComponent(0.02),
        NSColor.clear
    ],
    angle: 122
)

drawWaveField()
drawAudioHalo()
drawHeadphones()
drawBottomDivider()
drawEdgeTreatments(in: iconRect)

context.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode icon image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)

func drawHeadphones() {
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + 24)

    let halo = NSBezierPath(ovalIn: CGRect(x: center.x - 250, y: center.y - 258, width: 500, height: 500))
    halo.lineWidth = 28
    Palette.champagne.withAlphaComponent(0.32).setStroke()
    halo.stroke()

    let secondaryHalo = NSBezierPath(ovalIn: CGRect(x: center.x - 198, y: center.y - 206, width: 396, height: 396))
    secondaryHalo.lineWidth = 10
    Palette.ivory.withAlphaComponent(0.16).setStroke()
    secondaryHalo.stroke()

    let bandShadow = NSShadow()
    bandShadow.shadowColor = Palette.shadow
    bandShadow.shadowBlurRadius = 30
    bandShadow.shadowOffset = CGSize(width: 0, height: -14)

    let outerBand = NSBezierPath()
    outerBand.lineWidth = 92
    outerBand.lineCapStyle = .round
    outerBand.lineJoinStyle = .round
    outerBand.appendArc(
        withCenter: CGPoint(x: center.x, y: center.y + 70),
        radius: 224,
        startAngle: 208,
        endAngle: -28,
        clockwise: true
    )
    bandShadow.set()
    Palette.graphiteSurface.setStroke()
    outerBand.stroke()

    let innerBand = NSBezierPath()
    innerBand.lineWidth = 56
    innerBand.lineCapStyle = .round
    innerBand.appendArc(
        withCenter: CGPoint(x: center.x, y: center.y + 72),
        radius: 220,
        startAngle: 208,
        endAngle: -28,
        clockwise: true
    )
    Palette.graphiteSurfaceSoft.setStroke()
    innerBand.stroke()

    let accentBand = NSBezierPath()
    accentBand.lineWidth = 9
    accentBand.lineCapStyle = .round
    accentBand.appendArc(
        withCenter: CGPoint(x: center.x, y: center.y + 86),
        radius: 204,
        startAngle: 214,
        endAngle: -34,
        clockwise: true
    )
    Palette.champagne.withAlphaComponent(0.88).setStroke()
    accentBand.stroke()

    drawStem(
        from: CGPoint(x: 360, y: 632),
        to: CGPoint(x: 330, y: 542),
        control1: CGPoint(x: 350, y: 604),
        control2: CGPoint(x: 340, y: 572)
    )
    drawStem(
        from: CGPoint(x: 664, y: 632),
        to: CGPoint(x: 694, y: 542),
        control1: CGPoint(x: 674, y: 604),
        control2: CGPoint(x: 684, y: 572)
    )

    drawCup(rect: CGRect(x: 228, y: 280, width: 216, height: 318), tilt: -10)
    drawCup(rect: CGRect(x: 580, y: 280, width: 216, height: 318), tilt: 10)
}

func drawStem(from: CGPoint, to: CGPoint, control1: CGPoint, control2: CGPoint) {
    let stem = NSBezierPath()
    stem.lineWidth = 34
    stem.lineCapStyle = .round
    stem.move(to: from)
    stem.curve(to: to, controlPoint1: control1, controlPoint2: control2)
    Palette.graphiteSurface.setStroke()
    stem.stroke()

    let accent = NSBezierPath()
    accent.lineWidth = 6
    accent.lineCapStyle = .round
    accent.move(to: CGPoint(x: from.x + (to.x > from.x ? 8 : -8), y: from.y - 12))
    accent.curve(
        to: CGPoint(x: to.x + (to.x > from.x ? 8 : -8), y: to.y + 10),
        controlPoint1: CGPoint(x: control1.x + (to.x > from.x ? 8 : -8), y: control1.y - 4),
        controlPoint2: CGPoint(x: control2.x + (to.x > from.x ? 8 : -8), y: control2.y + 6)
    )
    Palette.champagne.withAlphaComponent(0.72).setStroke()
    accent.stroke()
}

func drawCup(rect: CGRect, tilt: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = Palette.shadow
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = CGSize(width: tilt * 0.3, height: -18)
    shadow.set()

    let cupPath = NSBezierPath(roundedRect: rect, xRadius: 96, yRadius: 96)
    let cupGradient = NSGradient(colors: [
        Palette.graphiteSurfaceSoft,
        NSColor(hex: 0x1A1D21),
        Palette.graphite
    ])!
    context.saveGState()
    cupPath.addClip()
    cupGradient.draw(in: rect, angle: tilt > 0 ? -18 : 18)
    context.restoreGState()

    Palette.champagne.withAlphaComponent(0.34).setStroke()
    cupPath.lineWidth = 5
    cupPath.stroke()

    let inset = rect.insetBy(dx: 26, dy: 42)
    let innerPad = NSBezierPath(roundedRect: inset, xRadius: 64, yRadius: 64)
    let padGradient = NSGradient(colors: [
        NSColor(hex: 0x0A0B0D),
        NSColor(hex: 0x1A1C20)
    ])!
    context.saveGState()
    innerPad.addClip()
    padGradient.draw(in: inset, angle: 90)
    context.restoreGState()

    Palette.ivory.withAlphaComponent(0.06).setStroke()
    innerPad.lineWidth = 3
    innerPad.stroke()

    let highlightRect = CGRect(
        x: rect.minX + (tilt < 0 ? 38 : rect.width - 84),
        y: rect.maxY - 98,
        width: 42,
        height: 138
    )
    let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: 20, yRadius: 20)
    Palette.ivory.withAlphaComponent(0.08).setFill()
    highlightPath.fill()
}

func drawAudioHalo() {
    for index in 0 ..< 3 {
        let inset = CGFloat(index) * 46
        let ring = NSBezierPath(ovalIn: CGRect(x: 214 + inset, y: 194 + inset, width: 596 - inset * 2, height: 596 - inset * 2))
        ring.lineWidth = index == 0 ? 8 : 4
        let alpha = index == 0 ? 0.16 : 0.08
        Palette.ivory.withAlphaComponent(alpha).setStroke()
        ring.stroke()
    }
}

func drawWaveField() {
    for index in 0 ..< 4 {
        let wave = NSBezierPath()
        wave.lineWidth = index == 0 ? 20 : 10
        wave.lineCapStyle = .butt
        let xOffset = CGFloat(index) * 44
        wave.move(to: CGPoint(x: 590 + xOffset, y: 168))
        wave.curve(
            to: CGPoint(x: 822 + xOffset * 0.28, y: 842),
            controlPoint1: CGPoint(x: 708 + xOffset, y: 340),
            controlPoint2: CGPoint(x: 726 + xOffset * 0.4, y: 652)
        )
        Palette.champagne.withAlphaComponent(index == 0 ? 0.12 : 0.06).setStroke()
        wave.stroke()
    }
}

func drawBottomDivider() {
    let dividerRect = CGRect(x: 330, y: 198, width: 364, height: 10)
    let divider = NSBezierPath(roundedRect: dividerRect, xRadius: 5, yRadius: 5)
    let dividerGradient = NSGradient(colors: [
        Palette.champagne.withAlphaComponent(0.0),
        Palette.champagne.withAlphaComponent(0.85),
        Palette.champagne.withAlphaComponent(0.0)
    ])!
    context.saveGState()
    divider.addClip()
    dividerGradient.draw(in: dividerRect, angle: 0)
    context.restoreGState()
}

func drawEdgeTreatments(in rect: CGRect) {
    let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), xRadius: 212, yRadius: 212)
    stroke.lineWidth = 5
    Palette.ivory.withAlphaComponent(0.14).setStroke()
    stroke.stroke()

    let innerStroke = NSBezierPath(roundedRect: rect.insetBy(dx: 18, dy: 18), xRadius: 188, yRadius: 188)
    innerStroke.lineWidth = 2
    Palette.ivory.withAlphaComponent(0.05).setStroke()
    innerStroke.stroke()
}

func drawOuterShadow(in context: CGContext, rect: CGRect) {
    context.saveGState()
    let path = NSBezierPath(roundedRect: rect, xRadius: 214, yRadius: 214)
    let shadow = NSShadow()
    shadow.shadowColor = Palette.shadow
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = CGSize(width: 0, height: -16)
    shadow.set()
    NSColor.black.withAlphaComponent(0.14).setFill()
    path.fill()
    context.restoreGState()
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
