// Renders Spanner's app icon (glassy squircle + chrome wrench) once at
// 1024 px, then writes the AppIcon asset at every size macOS needs and the
// README logo. Run: swift scripts/make-icon.swift
import AppKit

let iconDir = URL(fileURLWithPath: "Spanner/Resources/Assets.xcassets/AppIcon.appiconset")
let logo = URL(fileURLWithPath: "assets/logo.png")
let size = 1024
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func bitmap() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Apple-style continuous-corner squircle (superellipse, n = 5).
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = Double(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// The wrench as an alpha mask, rotated and centred on the tile.
func wrenchMask(in body: CGRect) -> CGImage {
    let ctx = bitmap()
    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "wrench.adjustable.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let s = symbol.size
    symbol.draw(in: CGRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// Everything outside `mask`, for inner shadows.
func inverted(_ mask: CGImage) -> CGImage {
    let ctx = bitmap()
    ctx.setFillColor(color(0x000000))
    ctx.fill(canvas)
    ctx.setBlendMode(.destinationOut)
    ctx.draw(mask, in: canvas)
    return ctx.makeImage()!
}

/// The master icon at 1024 px, transparent outside the tile.
func renderMaster() -> CGImage {
    let ctx = bitmap()
    let body = canvas.insetBy(dx: 100, dy: 100)
    let tile = squircle(in: body)

    // Tile: drop shadow, then a deep indigo-to-violet body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x0B0630, 0.45))
    ctx.addPath(tile)
    ctx.setFillColor(color(0x2A1F8F))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0x8C7BFF)), (0.45, color(0x5B44E8)), (1, color(0x23157A))]),
                           start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Soft light from the top left and a cool bounce from the bottom right.
    ctx.drawRadialGradient(gradient([(0, color(0xFFFFFF, 0.38)), (1, color(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: body.minX + 160, y: body.maxY - 120), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + 160, y: body.maxY - 120), endRadius: 620, options: [])
    ctx.drawRadialGradient(gradient([(0, color(0x3FD0FF, 0.30)), (1, color(0x3FD0FF, 0))]),
                           startCenter: CGPoint(x: body.maxX - 80, y: body.minY + 60), startRadius: 0,
                           endCenter: CGPoint(x: body.maxX - 80, y: body.minY + 60), endRadius: 520, options: [])
    ctx.restoreGState()

    // Wrench: cast shadow, chrome body, then bevel highlights.
    let mask = wrenchMask(in: body)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 14, height: -30), blur: 46, color: color(0x0A0530, 0.6))
    ctx.draw(mask, in: canvas)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.clip(to: canvas, mask: mask)
    ctx.drawLinearGradient(gradient([
        (0.00, color(0xFFFFFF)), (0.22, color(0xE4E8EF)), (0.40, color(0x9AA3B2)),
        (0.52, color(0xF4F6FA)), (0.70, color(0xB8BFCB)), (0.88, color(0x6E7686)), (1.00, color(0x9EA6B4)),
    ]), start: CGPoint(x: 330, y: 760), end: CGPoint(x: 700, y: 260), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Brushed-metal sheen across the handle.
    ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0)), (0.5, color(0xFFFFFF, 0.35)), (1, color(0xFFFFFF, 0))]),
                           start: CGPoint(x: 380, y: 380), end: CGPoint(x: 520, y: 520), options: [])
    // Inner shadow on the lower edge and a bright rim on the upper edge.
    let outside = inverted(mask)
    ctx.setShadow(offset: CGSize(width: -3, height: 6), blur: 10, color: color(0x1A1440, 0.55))
    ctx.draw(outside, in: canvas)
    ctx.setShadow(offset: CGSize(width: 3, height: -5), blur: 4, color: color(0xFFFFFF, 0.9))
    ctx.draw(outside, in: canvas)
    ctx.restoreGState()

    // Glass edge: bright rim at the top fading out toward the bottom.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.setLineWidth(5)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0.55)), (0.5, color(0xFFFFFF, 0.08)), (1, color(0xFFFFFF, 0.18))]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func png(_ master: CGImage, size px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let master = renderMaster()
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try png(master, size: points * scale).write(to: iconDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDir.appendingPathComponent("Contents.json"))
try FileManager.default.createDirectory(at: logo.deletingLastPathComponent(), withIntermediateDirectories: true)
try png(master, size: 512).write(to: logo)
print("wrote \(images.count) icons to \(iconDir.path) and \(logo.path)")
