import CoreGraphics
import Foundation

/// A session event tap on the main run loop that calls a closure for each
/// event. Used by the modules that watch or rewrite input (mouse fixes,
/// drag snapping, display media keys).
///
/// Phase 0 found that `tapCreate` succeeds without permission and the tap
/// then receives nothing, so owners install it only once Accessibility is
/// granted. A tap that modifies events (`listenOnly: false`) also needs it.
final class EventTap {
    enum Result {
        /// Let the event through (possibly after modifying it in place).
        case pass
        /// Swallow the event.
        case drop
    }

    typealias Handler = (CGEventType, CGEvent) -> Result

    /// Marks events Spanner posts itself so taps can let them through
    /// untouched instead of processing them again ("SPNR").
    static let syntheticMarker: Int64 = 0x5350_4E52

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler

    var isInstalled: Bool { tap != nil }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Installs and enables the tap. Returns false when macOS refuses it.
    @discardableResult
    func install(events: [CGEventType], listenOnly: Bool) -> Bool {
        guard tap == nil else { return true }
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: listenOnly ? .listenOnly : .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's run loop source is on the main run loop.
            let result = MainActor.assumeIsolated { owner.handle(type, event) }
            return result == .drop ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func remove() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Result {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables a tap whose callback was slow; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .pass
        default:
            if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return .pass }
            return handler(type, event)
        }
    }

    /// Posts a key press (down and up) carrying the synthetic marker.
    static func postKeystroke(keyCode: UInt16, flags: UInt64) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
