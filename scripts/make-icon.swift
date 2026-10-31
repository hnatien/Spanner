// Renders Spanner's app icon (gradient squircle + wrench symbol) into the
// AppIcon asset at every size macOS needs. Run: swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "Spanner/Resources/Assets.xcassets/AppIcon.appiconset")

func render(size: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // macOS icon grid: artwork is 824/1024 of the canvas, centred.
        let inset = rect.width * (100.0 / 1024.0)
        let body = rect.insetBy(dx: inset, dy: inset)
        let radius = body.width * 0.225
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = rect.width * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.01)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.47, green: 0.42, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.27, green: 0.24, blue: 0.75, alpha: 1),
        ])!
        gradient.draw(in: path, angle: -90)

        // Soft top highlight.
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        highlight.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()

        let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.46, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "wrench.adjustable.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = symbol.size
            symbol.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try render(size: CGFloat(points * scale)).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(output.path)")
