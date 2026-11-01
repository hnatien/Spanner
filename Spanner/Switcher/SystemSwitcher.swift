import ApplicationServices
import Foundation
import SpannerCore

// Private SkyLight / CoreGraphics Services calls, declared as AltTab does.
// Phase 0 confirmed they work on macOS 27.2 without any permission.

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
nonisolated func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
nonisolated func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

/// Maps an Accessibility window element to its window server ID.
@_silgen_name("_AXUIElementGetWindow")
nonisolated func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("CGSMainConnectionID")
nonisolated func CGSMainConnectionID() -> Int32

/// The Spaces holding each window; empty for windows ordered out.
/// Mask 7 = all Space kinds.
@_silgen_name("CGSCopySpacesForWindows")
nonisolated func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

/// Per display: its Spaces and the one currently shown.
@_silgen_name("CGSCopyManagedDisplaySpaces")
nonisolated func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// Owns the macOS Command-Tab shortcut while the Command-Tab trigger is in
/// use. See `SystemSwitcherPolicy` for why the ledger exists.
enum SystemSwitcher {
    /// Symbolic hotkey IDs: 1 = ⌘⇥, 2 = ⌘⇧⇥.
    private static let hotkeys: [Int32] = [1, 2]
    private static let ledgerKey = "switcher.systemShortcutDisabledBySpanner"

    /// Mirrors the ledger in memory so the signal handler needn't touch
    /// UserDefaults. Only written on the main thread.
    nonisolated(unsafe) private static var disabledBySpanner = false

    static var isSystemShortcutEnabled: Bool {
        hotkeys.allSatisfy { CGSIsSymbolicHotKeyEnabled($0) }
    }

    /// Applies the policy for the current desired state. Call on launch,
    /// whenever settings or permissions change, and on quit (with false).
    static func reconcile(wantsTakeover: Bool) {
        let ledger = UserDefaults.standard.bool(forKey: ledgerKey)
        disabledBySpanner = ledger
        switch SystemSwitcherPolicy.action(wantsTakeover: wantsTakeover, ledgerSaysDisabledByUs: ledger,
                                           systemShortcutEnabled: isSystemShortcutEnabled) {
        case .disable:
            UserDefaults.standard.set(true, forKey: ledgerKey)
            disabledBySpanner = true
            hotkeys.forEach { CGSSetSymbolicHotKeyEnabled($0, false) }
        case .restore:
            hotkeys.forEach { CGSSetSymbolicHotKeyEnabled($0, true) }
            UserDefaults.standard.set(false, forKey: ledgerKey)
            disabledBySpanner = false
        case .none:
            break
        }
    }

    /// Restores Command-Tab if Spanner is killed (`kill`, logout, Xcode stop).
    /// A hard crash can't be caught; the ledger handles that on next launch.
    static func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig) { received in
                SystemSwitcher.restoreFromSignalHandler()
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }

    nonisolated private static func restoreFromSignalHandler() {
        guard disabledBySpanner else { return }
        CGSSetSymbolicHotKeyEnabled(1, true)
        CGSSetSymbolicHotKeyEnabled(2, true)
        // The ledger stays set; the next launch sees the shortcut enabled
        // and clears it (the "stale ledger" case).
    }
}
