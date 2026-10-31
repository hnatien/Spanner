import CoreGraphics
import Foundation

/// Tells the switcher when the person lets go of the trigger modifier.
///
/// Primary signal: a listen-only session event tap on flagsChanged. Phase 0
/// showed it needs Accessibility (or Input Monitoring) and that creating it
/// succeeds even without permission and then silently receives nothing, so
/// it is only installed once Accessibility is granted. A light poll of the
/// modifier state backs it up while a session is open, in case the tap is
/// throttled by the system.
final class ModifierReleaseMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pollTimer: Timer?
    private var mask: UInt64 = 0
    private var onRelease: (() -> Void)?

    var isTapInstalled: Bool { tap != nil }

    func installTap() {
        guard tap == nil else { return }
        let events = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: events, callback: { _, type, event, userInfo in
            if let userInfo {
                let monitor = Unmanaged<ModifierReleaseMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let flags = event.flags.rawValue
                // The tap's run loop source is on the main run loop.
                MainActor.assumeIsolated { monitor.handle(type: type, flags: flags) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    func removeTap() {
        end()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    /// Starts watching for `mask` to be released. Calls `onRelease`
    /// immediately if it is already up (a very fast tap of the shortcut).
    func begin(mask: UInt64, onRelease: @escaping () -> Void) {
        self.mask = mask
        self.onRelease = onRelease
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCurrentState() }
        }
        checkCurrentState()
    }

    func end() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        pollTimer?.invalidate()
        pollTimer = nil
        onRelease = nil
    }

    private func handle(type: CGEventType, flags: UInt64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if onRelease != nil, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            if flags & mask == 0 { fire() }
        default:
            break
        }
    }

    private func checkCurrentState() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        if flags & mask == 0 { fire() }
    }

    private func fire() {
        guard let onRelease else { return }
        end()
        onRelease()
    }
}
