import AppKit
import ApplicationServices

/// Reads and sets window frames through Accessibility. All frames are in
/// Accessibility coordinates (top-left origin).
enum WindowMover {
    private static let messagingTimeout: Float = 0.25

    /// The focused window of the frontmost app.
    static func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window: AXUIElement = copy(app, kAXFocusedWindowAttribute) else { return nil }
        return isMovable(window) ? window : nil
    }

    /// The window under an Accessibility-space point.
    static func window(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        if role(of: hit) == kAXWindowRole { return isMovable(hit) ? hit : nil }
        guard let window: AXUIElement = copy(hit, kAXWindowAttribute) else { return nil }
        return isMovable(window) ? window : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copy(window, kAXPositionAttribute),
              let sizeValue: AXValue = copy(window, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Moves and resizes a window. Size is set before and after the move:
    /// a window can't grow past the edge of its current screen, so a big
    /// target on another screen only fits once it has moved there.
    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        let app = application(of: window)
        // Apps with enhanced UI on (set by assistive tools) animate each
        // attribute change, which leaves the window half-moved.
        let enhanced = app.flatMap { boolValue($0, "AXEnhancedUserInterface") } ?? false
        if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
        if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    /// Standard windows that aren't fullscreen and whose position can change.
    private static func isMovable(_ window: AXUIElement) -> Bool {
        if boolValue(window, "AXFullScreen") == true { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func application(of window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static func role(of element: AXUIElement) -> String? {
        copy(element, kAXRoleAttribute)
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as CFBoolean?).map(CFBooleanGetValue)
    }

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
