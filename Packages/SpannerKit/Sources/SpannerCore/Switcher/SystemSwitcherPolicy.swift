import Foundation

/// Decides what to do with the macOS Command-Tab shortcut.
///
/// Disabling it (CGSSetSymbolicHotKeyEnabled) outlives Spanner: if Spanner
/// crashes while the shortcut is off, Command-Tab stays dead until something
/// turns it back on. So Spanner keeps a ledger flag ("we turned it off") in
/// UserDefaults and consults it on every launch and quit. Spanner only ever
/// re-enables a shortcut it disabled itself, so it never fights another app
/// that also replaces Command-Tab.
public enum SystemSwitcherPolicy {
    public enum Action: Equatable, Sendable {
        /// Turn the system shortcut off and record that we did.
        case disable
        /// Turn the system shortcut back on and clear the record.
        case restore
        /// Leave everything as it is.
        case none
    }

    /// - Parameters:
    ///   - wantsTakeover: Spanner should own Command-Tab right now (enabled,
    ///     permitted, and the Command-Tab trigger chosen). False on quit.
    ///   - ledgerSaysDisabledByUs: the persisted flag from a previous disable.
    ///   - systemShortcutEnabled: current state reported by the window server.
    public static func action(wantsTakeover: Bool,
                              ledgerSaysDisabledByUs: Bool,
                              systemShortcutEnabled: Bool) -> Action {
        if wantsTakeover {
            // Already off: either we did it earlier (ledger set) or another
            // app did. Either way there is nothing to switch.
            return systemShortcutEnabled ? .disable : .none
        }
        if ledgerSaysDisabledByUs {
            // Covers the crash case on relaunch, and clears a stale ledger if
            // the shortcut was already turned back on by someone else.
            return .restore
        }
        return .none
    }
}
