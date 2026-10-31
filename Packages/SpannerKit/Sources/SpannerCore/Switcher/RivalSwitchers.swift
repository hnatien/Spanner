import Foundation

/// Other window switchers that grab the same shortcuts. When one is running,
/// Carbon gives the shortcut to whichever app registered first, so the
/// person may see the other app's switcher and think Spanner's is broken.
public enum RivalSwitchers {
    /// Bundle identifier → display name. AltTab's ID is verified on a real
    /// install; Witch and Contexts follow their vendors' naming.
    public static let known: [String: String] = [
        "com.lwouis.alt-tab-macos": "AltTab",
        "com.manytricks.Witch": "Witch",
        "com.manytricks.WitchDaemon": "Witch",
        "com.contextsformac.Contexts": "Contexts",
    ]

    /// Names of known switchers among the running bundle IDs, deduplicated
    /// and sorted so the UI is stable.
    public static func running(in bundleIDs: some Sequence<String>) -> [String] {
        Array(Set(bundleIDs.compactMap { known[$0] })).sorted()
    }
}
