import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures and caches window thumbnails with ScreenCaptureKit.
///
/// Rules from the research and Phase 0: single screenshots only, never
/// continuous SCStreams (background capture destabilised WindowServer for
/// AltTab users); thumbnail-sized; captures only while the switcher is open;
/// and a "successful" capture can be blank, so blank images are discarded
/// and the tile falls back to the app icon. Captures run one at a time:
/// each takes 7–47 ms (Phase 0), results stream to the UI as they land, and
/// it keeps WindowServer load at a minimum.
actor ThumbnailCapturer {
    private var images: [CGWindowID: CGImage] = [:]
    private var shareable: [CGWindowID: SCWindow] = [:]
    private var shareableFetchedAt = Date.distantPast

    func cachedImages(for ids: [CGWindowID]) -> [CGWindowID: CGImage] {
        images.filter { ids.contains($0.key) }
    }

    /// Captures `ids` in order, reporting each image (nil when blank or
    /// failed) through `deliver`. Stops early if the calling task is cancelled.
    /// Returns false when ScreenCaptureKit refused for lack of permission
    /// (macOS shows its Screen Recording alert on every such call).
    func capture(_ ids: [CGWindowID], maxPixelWidth: Int,
                 deliver: @MainActor @Sendable (CGWindowID, CGImage?) -> Void) async -> Bool {
        guard await refreshShareableContentIfStale() else { return false }
        for id in ids {
            guard !Task.isCancelled else { return true }
            guard let window = shareable[id] else { continue }
            let image = await Self.screenshot(of: window, maxPixelWidth: maxPixelWidth)
            if let image, !Self.isBlank(image) {
                images[id] = image
                await deliver(id, image)
            } else if images[id] == nil {
                await deliver(id, nil)
            }
        }
        return true
    }

    /// Drops images for windows that no longer exist.
    func prune(keeping live: Set<CGWindowID>) {
        images = images.filter { live.contains($0.key) }
    }

    /// Returns false only when access was declined; other failures keep
    /// the previous list.
    private func refreshShareableContentIfStale() async -> Bool {
        guard Date.now.timeIntervalSince(shareableFetchedAt) > 2 else { return true }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            shareable = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            shareableFetchedAt = .now
            return true
        } catch let error as SCStreamError where error.code == .userDeclined {
            return false
        } catch {
            return true
        }
    }

    private static func screenshot(of window: SCWindow, maxPixelWidth: Int) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let scale = min(1, Double(maxPixelWidth) / frame.width)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // The macOS 27 SDK imports only the completion-handler form.
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// True when every sampled pixel is identical (Phase 0's blank windows
    /// came back as solid white).
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return stride(from: 4, to: pixels.count, by: 4).allSatisfy { pixels[$0..<$0 + 4].elementsEqual(pixels[0..<4]) }
    }
}
