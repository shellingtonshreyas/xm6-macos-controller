import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: swift generate_app_icon.swift /output/path/icon.png [/source/image]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let sourceImageURL = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2]) : nil
let size = NSSize(width: 1024, height: 1024)

let image = NSImage(size: size, flipped: false) { rect in
    NSColor.white.setFill()
    rect.fill()

    if let sourceImageURL,
       let sourceImage = NSImage(contentsOf: sourceImageURL)
    {
        let canvas = CGRect(x: 72, y: 92, width: 880, height: 840)
        let sourceSize = sourceImage.size
        if sourceSize.width > 0, sourceSize.height > 0 {
            let scale = min(canvas.width / sourceSize.width, canvas.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawRect = CGRect(
                x: canvas.midX - drawSize.width / 2,
                y: canvas.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            sourceImage.draw(in: drawRect)
            return true
        }
    }

    let center = CGPoint(x: rect.midX, y: rect.midY)

    let headband = NSBezierPath()
    headband.lineWidth = 54
    headband.lineCapStyle = .round
    headband.lineJoinStyle = .round
    headband.appendArc(
        withCenter: center,
        radius: 248,
        startAngle: 202,
        endAngle: -22,
        clockwise: true
    )
    NSColor.black.setStroke()
    headband.stroke()

    let leftCup = NSBezierPath(roundedRect: CGRect(x: 258, y: 286, width: 138, height: 300), xRadius: 60, yRadius: 60)
    NSColor.black.setFill()
    leftCup.fill()

    let rightCup = NSBezierPath(roundedRect: CGRect(x: 628, y: 286, width: 138, height: 300), xRadius: 60, yRadius: 60)
    rightCup.fill()

    let leftPad = NSBezierPath(roundedRect: CGRect(x: 288, y: 338, width: 78, height: 196), xRadius: 36, yRadius: 36)
    NSColor.white.setFill()
    leftPad.fill()

    let rightPad = NSBezierPath(roundedRect: CGRect(x: 658, y: 338, width: 78, height: 196), xRadius: 36, yRadius: 36)
    rightPad.fill()

    let leftStem = NSBezierPath()
    leftStem.lineWidth = 42
    leftStem.lineCapStyle = .round
    leftStem.move(to: CGPoint(x: 356, y: 596))
    leftStem.curve(
        to: CGPoint(x: 338, y: 648),
        controlPoint1: CGPoint(x: 350, y: 612),
        controlPoint2: CGPoint(x: 344, y: 630)
    )
    NSColor.black.setStroke()
    leftStem.stroke()

    let rightStem = NSBezierPath()
    rightStem.lineWidth = 42
    rightStem.lineCapStyle = .round
    rightStem.move(to: CGPoint(x: 668, y: 596))
    rightStem.curve(
        to: CGPoint(x: 686, y: 648),
        controlPoint1: CGPoint(x: 674, y: 612),
        controlPoint2: CGPoint(x: 680, y: 630)
    )
    rightStem.stroke()

    return true
}

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fputs("Failed to encode icon image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
