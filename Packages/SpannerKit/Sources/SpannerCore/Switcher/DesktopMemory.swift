import Foundation

/// One display's Spaces as the window server reports them.
public struct DisplaySpaces: Equatable, Sendable {
    public let display: String
    /// The Space the display is showing.
    public let current: Int
    /// The display's ordinary desktop Spaces, in Mission Control order.
    /// Full-screen Spaces are not listed.
    public let desktops: [Int]

    public init(display: String, current: Int, desktops: [Int]) {
        self.display = display
        self.current = current
        self.desktops = desktops
    }
}

/// Remembers the desktop each display last showed, so that while a
/// full-screen Space is up the desktop the user came from still counts as
/// the one they are on, and its windows are not "on another Space" in any
/// sense they care about. This is a best guess: the window server does not
/// say which desktop a full-screen Space sits over, and leaving full screen
/// can land on a different one.
public struct DesktopMemory: Equatable, Sendable {
    private var lastDesktop: [String: Int] = [:]

    public init() {}

    /// Records every display that is showing a desktop, and forgets
    /// displays no longer attached.
    public mutating func note(_ displays: [DisplaySpaces]) {
        let attached = Set(displays.map(\.display))
        lastDesktop = lastDesktop.filter { attached.contains($0.key) }
        for display in displays where display.desktops.contains(display.current) {
            lastDesktop[display.display] = display.current
        }
    }

    /// Desktops hidden under the full-screen Space their display is showing.
    /// A display with several desktops and none remembered is left out, since
    /// which one macOS returns to is then unknown.
    public func coveredDesktops(_ displays: [DisplaySpaces]) -> Set<Int> {
        Set(displays.compactMap { display in
            guard !display.desktops.contains(display.current) else { return nil }
            if let last = lastDesktop[display.display], display.desktops.contains(last) { return last }
            return display.desktops.count == 1 ? display.desktops[0] : nil
        })
    }
}
