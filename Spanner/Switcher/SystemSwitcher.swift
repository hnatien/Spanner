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

/// False for a window its app closed but kept alive; true for one that is
/// merely on a Space not being shown.
@_silgen_name("CGSWindowIsOrderedIn")
nonisolated func CGSWindowIsOrderedIn(_ connection: Int32, _ windowID: CGWindowID,
                                      _ isOrderedIn: UnsafeMutablePointer<DarwinBoolean>) -> CGError

@_silgen_name("GetProcessForPID")
nonisolated func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

/// SkyLight calls that CoreGraphics does not re-export, looked up at run
/// time so a macOS without them falls back instead of failing to launch.
enum SkyLight {
    /// Makes a process frontmost. With `userGenerated` and a window ID only
    /// that window comes forward, unlike activating the app, which brings all
    /// of its windows above every other app's.
    typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32)
        -> CGError
    /// Posts a raw window server event record to a process.
    typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>)
        -> CGError

    static let userGenerated: UInt32 = 0x200

    static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions")
    static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

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
