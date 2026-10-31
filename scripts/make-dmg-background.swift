// Renders the DMG window background: a title, an arrow from the app icon to
// the Applications folder, and the first-launch steps. Writes a 1x + 2x TIFF
// that Finder picks the right resolution from. release.sh runs this and lays
// the icons out at the positions below, so keep the two in sync.
//
//   swift scripts/make-dmg-background.swift <output.tiff>
import AppKit

let width: CGFloat = 660, height: CGFloat = 460
let appCenter = CGPoint(x: 170, y: 185), applicationsCenter = CGPoint(x: 490, y: 185)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: swift scripts/make-dmg-background.swift <output.tiff>\n".data(using: .utf8)!)
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1,
          align: NSTextAlignment = .center) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = 1.5
    return NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .paragraphStyle: style,
    ])
}

/// Draws in points with a top-left origin, so coordinates match Finder's icon positions.
func render(scale: CGFloat) -> NSBitmapImageRep {
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: 0, y: -height)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Finder draws icon labels black in light mode and white in dark mode, so
    // the band behind them stays mid-luminance to keep both readable.
    ctx.drawLinearGradient(gradient([(0, color(0x5240C8)), (0.55, color(0x7A63E0)), (1, color(0x4A3AB8))]),
                           start: .zero, end: CGPoint(x: 0, y: height), options: [])
    ctx.drawRadialGradient(gradient([(0, color(0xD27BF2, 0.45)), (1, color(0xD27BF2, 0))]),
                           startCenter: CGPoint(x: 600, y: 20), startRadius: 0,
                           endCenter: CGPoint(x: 600, y: 20), endRadius: 340, options: [])
    ctx.drawRadialGradient(gradient([(0, color(0x4F8BF5, 0.4)), (1, color(0x4F8BF5, 0))]),
                           startCenter: CGPoint(x: 40, y: 420), startRadius: 0,
                           endCenter: CGPoint(x: 40, y: 420), endRadius: 360, options: [])

    // Soft halos behind the two icons.
    for center in [appCenter, applicationsCenter] {
        ctx.drawRadialGradient(gradient([(0, color(0xFFFFFF, 0.22)), (1, color(0xFFFFFF, 0))]),
                               startCenter: center, startRadius: 0, endCenter: center, endRadius: 92, options: [])
    }

    text("Install Spanner", size: 22, weight: .bold).draw(in: CGRect(x: 0, y: 26, width: width, height: 30))
    text("Drag the app onto your Applications folder", size: 13, weight: .medium, alpha: 0.8)
        .draw(in: CGRect(x: 0, y: 58, width: width, height: 20))

    // Dashed arc with an arrowhead between the icons.
    let start = CGPoint(x: appCenter.x + 84, y: appCenter.y - 4)
    let end = CGPoint(x: applicationsCenter.x - 84, y: applicationsCenter.y - 4)
    let control = CGPoint(x: (start.x + end.x) / 2, y: start.y - 46)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: color(0x1A1060, 0.35))
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 9])
    ctx.move(to: start)
    ctx.addQuadCurve(to: end, control: control)
    ctx.strokePath()
    let angle = atan2(end.y - control.y, end.x - control.x)
    let tip = CGPoint(x: end.x + 10 * cos(angle), y: end.y + 10 * sin(angle))
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: tip.x - 14 * cos(angle - 0.6), y: tip.y - 14 * sin(angle - 0.6)))
    ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: tip.x - 14 * cos(angle + 0.6), y: tip.y - 14 * sin(angle + 0.6)))
    ctx.strokePath()
    ctx.restoreGState()

    // First-launch guide.
    let panel = CGRect(x: 20, y: 302, width: width - 40, height: 138)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.addPath(panelPath)
    ctx.setFillColor(color(0x140C40, 0.32))
    ctx.fillPath()
    ctx.addPath(panelPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(1)
    ctx.strokePath()

    let steps = [
        ("Drag to install", "Drop Spanner onto the Applications folder above."),
        ("Open Anyway", "If macOS blocks the first launch, open System Settings › Privacy & Security and click Open Anyway."),
        ("Grant access", "Allow the permissions each module asks for. Spanner then lives in your menu bar."),
    ]
    let column = (panel.width - 32) / CGFloat(steps.count)
    for (index, (title, body)) in steps.enumerated() {
        let x = panel.minX + 16 + CGFloat(index) * column
        if index > 0 {
            ctx.setFillColor(color(0xFFFFFF, 0.12))
            ctx.fill(CGRect(x: x - 0.5, y: panel.minY + 20, width: 1, height: panel.height - 40))
        }
        let badge = CGRect(x: x + 12, y: panel.minY + 18, width: 22, height: 22)
        ctx.setFillColor(color(0xFFFFFF, 0.95))
        ctx.fillEllipse(in: badge)
        NSAttributedString(string: "\(index + 1)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor(cgColor: color(0x5A44D2))!,
        ]).draw(at: CGPoint(x: badge.midX - (index == 0 ? 3.5 : 4), y: badge.minY + 3.5))
        text(title, size: 13, weight: .semibold, align: .left)
            .draw(in: CGRect(x: badge.maxX + 9, y: badge.minY + 2.5, width: column - 56, height: 18))
        text(body, size: 11, weight: .regular, alpha: 0.82, align: .left)
            .draw(in: CGRect(x: x + 12, y: badge.maxY + 10, width: column - 24, height: 70))
    }

    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height)
    return rep
}

guard let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)],
                                                                using: .lzw, factor: 0) else {
    FileHandle.standardError.write("Could not encode the background TIFF.\n".data(using: .utf8)!)
    exit(1)
}
try tiff.write(to: output)
