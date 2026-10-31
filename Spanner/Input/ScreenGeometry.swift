import AppKit
import SpannerCore

/// Screen facts in the Accessibility coordinate space (top-left origin of
/// the primary screen, y down), which is what AX window frames and CGEvent
/// locations use.
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stable across reboots and reconnections: vendor, model and serial
    /// from the display's EDID. Used to remember per-display settings.
    var persistentKey: String {
        guard let id = displayID else { return localizedName }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    private static var primaryHeight: Double {
        Double(NSScreen.screens.first?.frame.height ?? 0)
    }

    var axFrame: CGRect { SnapGeometry.flip(frame, primaryScreenHeight: Self.primaryHeight) }
    var axVisibleFrame: CGRect { SnapGeometry.flip(visibleFrame, primaryScreenHeight: Self.primaryHeight) }

    /// Converts an Accessibility rect to AppKit window coordinates.
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        SnapGeometry.flip(rect, primaryScreenHeight: primaryHeight)
    }

    /// The screen containing an Accessibility-space point.
    static func screen(containingAX point: CGPoint) -> NSScreen? {
        screens.first { $0.axFrame.contains(point) }
    }

    /// The screen showing most of an Accessibility-space rect.
    static func screen(forAX rect: CGRect) -> NSScreen? {
        if let byCenter = screen(containingAX: CGPoint(x: rect.midX, y: rect.midY)) { return byCenter }
        return screens.max { area($0.axFrame.intersection(rect)) < area($1.axFrame.intersection(rect)) }
    }

    private static func area(_ rect: CGRect) -> Double {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
