import Foundation

/// Everything the switcher knows about one window, merged from the window
/// server list (CGWindowList) and the owning app's Accessibility tree.
public struct WindowCandidate: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let pid: Int32
    public let appName: String
    /// Accessibility title if known, else the window server name, else "".
    public let title: String
    public let width: Double
    public let height: Double
    public let layer: Int
    public let isOnScreen: Bool
    public let hasAXElement: Bool
    public let isMinimized: Bool
    /// Off screen although its app is not hidden, and not on a Space the user
    /// can't currently see: the app closed it but kept it alive (as FaceTime
    /// and Chrome do), so it is not really there. See `WindowPlacement`.
    public let isOrderedOut: Bool
    /// Off screen only because a full-screen Space covers the desktop it is
    /// on, so it is still on the user's current desktop.
    public let isBehindFullScreen: Bool

    public init(id: UInt32, pid: Int32, appName: String, title: String, width: Double, height: Double,
                layer: Int, isOnScreen: Bool, hasAXElement: Bool, isMinimized: Bool, isOrderedOut: Bool = false,
                isBehindFullScreen: Bool = false) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.width = width
        self.height = height
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.hasAXElement = hasAXElement
        self.isMinimized = isMinimized
        self.isOrderedOut = isOrderedOut
        self.isBehindFullScreen = isBehindFullScreen
    }

    /// Not visible, not minimized, not just behind full screen: on another
    /// Space or in a hidden app.
    public var isElsewhere: Bool { !isOnScreen && !isMinimized && !isBehindFullScreen }
}

/// Works out why an off-screen window of a visible app is off screen, from
/// what the window server says about it.
public enum WindowPlacement {
    /// - Parameters:
    ///   - isOrderedIn: the window server's ordered-in flag, nil if the call
    ///     failed. A minimized window is not ordered in either, and keeps its
    ///     Space just as a closed-but-retained one does, so `false` alone
    ///     does not mean the window is gone.
    ///   - spaces: the window's Spaces, nil if the lookup failed. Only read
    ///     when the answer depends on it.
    ///   - visibleSpaces: the Space each display is showing.
    ///   - coveredDesktops: desktops hidden under a full-screen Space.
    public static func classify(isOrderedIn: Bool?, spaces: () -> [Int]?, visibleSpaces: Set<Int>,
                                coveredDesktops: Set<Int>) -> (isOrderedOut: Bool, isBehindFullScreen: Bool) {
        if isOrderedIn == true {
            guard !coveredDesktops.isEmpty, let spaces = spaces() else { return (false, false) }
            return (false, !coveredDesktops.isDisjoint(with: spaces))
        }
        // Not ordered in, or unknown. A window on no Space was closed; one on
        // a Space being shown would be on screen unless closed or minimized,
        // and a minimized one is kept by its minimized flag. One on a Space
        // not being shown may just be minimized there, so it is kept as
        // elsewhere rather than dropped.
        guard let spaces = spaces() else { return (false, false) }
        return (spaces.isEmpty || !visibleSpaces.isDisjoint(with: spaces), false)
    }
}

public struct WindowListOptions: Equatable, Sendable {
    public var includeMinimized: Bool
    public var includeOtherSpaces: Bool
    public var minimumSize: Double
    /// Set for "windows of the current app" mode.
    public var onlyPID: Int32?

    public init(includeMinimized: Bool = true, includeOtherSpaces: Bool = true, minimumSize: Double = 80,
                onlyPID: Int32? = nil) {
        self.includeMinimized = includeMinimized
        self.includeOtherSpaces = includeOtherSpaces
        self.minimumSize = minimumSize
        self.onlyPID = onlyPID
    }
}

/// Turns raw candidates into the ordered list the switcher shows.
public enum WindowListBuilder {
    /// - Parameters:
    ///   - zOrder: on-screen window IDs, front to back.
    ///   - appRecency: process IDs, most recently activated first.
    /// - Returns: visible windows in z-order (so index 1 is the previously
    ///   used window), then the rest grouped by how recently their app was
    ///   used. Order is stable for equal keys.
    public static func build(_ candidates: [WindowCandidate], zOrder: [UInt32], appRecency: [Int32],
                             options: WindowListOptions) -> [WindowCandidate] {
        var seen = Set<UInt32>()
        let kept = candidates.filter { window in
            guard seen.insert(window.id).inserted else { return false }
            return isEligible(window, options: options)
        }

        let zRank = Dictionary(zOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let appRank = Dictionary(appRecency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let unranked = Int.max

        return kept.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let aVisible = a.isOnScreen && zRank[a.id] != nil
            let bVisible = b.isOnScreen && zRank[b.id] != nil
            if aVisible != bVisible { return aVisible }
            if aVisible {
                return zRank[a.id]! < zRank[b.id]!
            }
            let aApp = appRank[a.pid] ?? unranked, bApp = appRank[b.pid] ?? unranked
            if aApp != bApp { return aApp < bApp }
            if a.isMinimized != b.isMinimized { return !a.isMinimized }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func isEligible(_ window: WindowCandidate, options: WindowListOptions) -> Bool {
        guard window.layer == 0,
              window.width >= options.minimumSize, window.height >= options.minimumSize else { return false }
        if let only = options.onlyPID, window.pid != only { return false }
        // Untitled windows the app doesn't expose to Accessibility were the
        // invisible helper windows that captured blank in Phase 0.
        if window.title.isEmpty && !window.hasAXElement { return false }
        if window.isOrderedOut && !window.isMinimized { return false }
        if window.isMinimized && !options.includeMinimized { return false }
        if window.isElsewhere && !options.includeOtherSpaces { return false }
        return true
    }
}
