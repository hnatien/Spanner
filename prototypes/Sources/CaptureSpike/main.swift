// Spike (a): Screen Recording permission behavior and thumbnail capture
// coverage on this macOS build. Run as its own .app (see bundle.sh).
//
//   capture-spike [--log PATH] [--out DIR] [--max N]
//
// Logs permission state, how many windows ScreenCaptureKit lists on and off
// the current Space, and per-window capture time and errors at thumbnail size.
// The periodic re-approval prompt cannot be observed in one run; the log
// records the date so a later run can be compared against it.

import AppKit
import ScreenCaptureKit

var options: [String: String] = [:]
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iterator.next() {
    if let value = iterator.next() { options[arg] = value }
}

let logURL = URL(fileURLWithPath: options["--log"] ?? NSTemporaryDirectory() + "capture-spike.log")
let outDir = URL(fileURLWithPath: options["--out"] ?? NSTemporaryDirectory())
let maxCaptures = options["--max"].flatMap(Int.init) ?? 16
let start = Date()

func log(_ message: String) {
    let line = String(format: "[%6.2fs] ", Date().timeIntervalSince(start)) + message + "\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

func savePNG(_ image: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) { log("saved \(url.path)") }
}

// A capture that "succeeds" can still be empty; treat an image whose sampled
// pixels are all identical as blank.
func isBlank(_ image: CGImage) -> Bool {
    let width = 32, height = 32
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let first = pixels[0..<4]
    return stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0..<$0 + 4].elementsEqual(first) }
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(at: outDir.appendingPathComponent("thumbs"), withIntermediateDirectories: true)

log("run at \(ISO8601DateFormatter().string(from: Date())) bundle=\(Bundle.main.bundleIdentifier ?? "none")")
log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
let preflight = CGPreflightScreenCaptureAccess()
log("CGPreflightScreenCaptureAccess=\(preflight)")
if !preflight {
    log("CGRequestScreenCaptureAccess -> \(CGRequestScreenCaptureAccess())")
}

do {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    let windows = content.windows.filter {
        $0.windowLayer == 0 && $0.owningApplication != nil && $0.frame.width > 80 && $0.frame.height > 80
    }
    let onScreen = windows.filter(\.isOnScreen)
    let titled = windows.filter { !($0.title ?? "").isEmpty }
    log("displays=\(content.displays.count) windows(normal)=\(windows.count) onScreen=\(onScreen.count) offScreen=\(windows.count - onScreen.count) withTitles=\(titled.count)")

    var okOn = 0, okOff = 0, failOn = 0, failOff = 0, blankOn = 0, blankOff = 0
    for window in windows.prefix(maxCaptures) {
        let config = SCStreamConfiguration()
        let scale = min(1, 320 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale * 2))
        config.height = max(1, Int(window.frame.height * scale * 2))
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let app = window.owningApplication?.applicationName ?? "?"
        let where_ = window.isOnScreen ? "on" : "off"
        let t0 = Date()
        do {
            // The macOS 27 SDK imports only the completion-handler form.
            let image: CGImage = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: error ?? CocoaError(.featureUnsupported)) }
                }
            }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let blank = isBlank(image)
            let title = window.title ?? ""
            log("ok   \(where_)-screen \(app) id=\(window.windowID) \(image.width)x\(image.height) \(ms)ms \(blank ? "BLANK" : "content") frame=\(Int(window.frame.width))x\(Int(window.frame.height)) title=\"\(title.prefix(40))\"")
            if window.isOnScreen { okOn += 1 } else { okOff += 1 }
            if blank { if window.isOnScreen { blankOn += 1 } else { blankOff += 1 } }
            savePNG(image, "thumbs/\(where_)-\(window.windowID).png")
        } catch {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let nsError = error as NSError
            log("FAIL \(where_)-screen \(app) id=\(window.windowID) \(ms)ms \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
            if window.isOnScreen { failOn += 1 } else { failOff += 1 }
        }
    }
    log("RESULT: on-screen ok=\(okOn) blank=\(blankOn) fail=\(failOn); off-screen ok=\(okOff) blank=\(blankOff) fail=\(failOff)")
} catch {
    let nsError = error as NSError
    log("SCShareableContent failed: \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
}
log("end: CGPreflightScreenCaptureAccess=\(CGPreflightScreenCaptureAccess())")
exit(0)
