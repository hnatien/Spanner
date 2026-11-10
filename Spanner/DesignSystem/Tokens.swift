import SwiftUI

/// Spacing scale shared by every surface (menu bar panel, main window,
/// switcher overlay) so layouts keep one rhythm.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii. Nested shapes use the next size down so curves stay
/// concentric (outer radius = inner radius + padding).
enum CornerRadius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
}

/// Feature colours, used for page icons and accents so each module is
/// recognisable at a glance, the way System Settings colours its panes.
enum FeatureTint {
    static let battery = Color.green
    static let system = Color.blue
    static let switcher = Color.indigo
    static let snapping = Color.cyan
    static let mouse = Color.pink
    static let sound = Color.red
    static let displays = Color.purple
    static let keepAwake = Color.orange
    static let features = Color.mint
    static let menuBar = Color.teal
    static let permissions = Color.blue
    static let general = Color.gray
    static let updates = Color.teal
}

extension Animation {
    /// Default motion for state changes: quick, slightly springy, never bouncy.
    static let spanner = Animation.spring(response: 0.32, dampingFraction: 0.86)
}
