import Foundation

/// Scroll direction for wheel mice, independent of the trackpad. macOS has
/// one "natural scrolling" switch shared by both.
public enum MouseScrollDirection: String, CaseIterable, Identifiable, Sendable, Codable {
    case followSystem, natural, standard

    public var id: Self { self }

    public var title: String {
        switch self {
        case .followSystem: "Same as trackpad"
        case .natural: "Natural"
        case .standard: "Standard"
        }
    }

    /// Whether a wheel event must be flipped. Trackpads and Magic Mouse send
    /// continuous events and are never touched; macOS has already applied
    /// its own natural-scrolling setting to the deltas of wheel events.
    public func invertsWheel(isContinuous: Bool, systemNatural: Bool) -> Bool {
        guard !isContinuous else { return false }
        switch self {
        case .followSystem: return false
        case .natural: return !systemNatural
        case .standard: return systemNatural
        }
    }
}

/// What an extra mouse button does.
public enum MouseButtonAction: String, CaseIterable, Identifiable, Sendable, Codable {
    case passThrough, back, forward, missionControl, appExpose, middleClick

    public var id: Self { self }

    public var title: String {
        switch self {
        case .passThrough: "Default"
        case .back: "Back (⌘[)"
        case .forward: "Forward (⌘])"
        case .missionControl: "Mission Control"
        case .appExpose: "App windows"
        case .middleClick: "Middle click"
        }
    }

    /// Key press that performs the action, as (virtual key code, CGEventFlags
    /// raw mask). Mission Control and App Exposé use their default shortcuts
    /// (⌃↑ and ⌃↓), so they follow the person's Keyboard settings.
    public var keystroke: (keyCode: UInt16, flags: UInt64)? {
        switch self {
        case .back: (0x21, 0x0010_0000)
        case .forward: (0x1E, 0x0010_0000)
        case .missionControl: (0x7E, 0x0004_0000)
        case .appExpose: (0x7D, 0x0004_0000)
        case .passThrough, .middleClick: nil
        }
    }
}

/// The extra buttons Spanner can remap, by CGEvent button number.
public enum MouseButton: Int, CaseIterable, Identifiable, Sendable, Codable {
    case middle = 2
    case back = 3
    case forward = 4

    public var id: Self { self }

    public var title: String {
        switch self {
        case .middle: "Middle button"
        case .back: "Button 4 (side, back)"
        case .forward: "Button 5 (side, forward)"
        }
    }

    /// Middle click stays a middle click unless changed; side buttons already
    /// mean back and forward in browsers, but not in most other apps.
    public var defaultAction: MouseButtonAction {
        switch self {
        case .middle: .passThrough
        case .back: .back
        case .forward: .forward
        }
    }

    /// Actions offered for this button (a middle button can't map to itself).
    public var choices: [MouseButtonAction] {
        MouseButtonAction.allCases.filter { !(self == .middle && $0 == .middleClick) }
    }
}

/// Turns notchy wheel ticks into a short glide of pixel scrolls.
///
/// Pure state: the controller feeds it wheel ticks and asks for the next
/// step on each display frame, then posts the result as a pixel scroll.
public struct SmoothScroller: Sendable {
    /// Pixels per wheel line at speed 1.
    public static let pixelsPerLine = 40.0

    /// Speed multiplier for one tick (0.5...3).
    public var speed: Double
    /// Glide time constant in seconds; larger is smoother and longer.
    public var smoothness: Double

    public private(set) var pendingX = 0.0
    public private(set) var pendingY = 0.0
    private var carryX = 0.0
    private var carryY = 0.0
    private var lastTick: TimeInterval = -.infinity
    private var streak = 0

    public init(speed: Double = 1, smoothness: Double = 0.09) {
        self.speed = speed
        self.smoothness = smoothness
    }

    public var isIdle: Bool { abs(pendingX) < 0.5 && abs(pendingY) < 0.5 }

    /// Adds a wheel tick of `lines` (signed, as in the wheel event). Quick
    /// successive ticks in the same direction accelerate, like a flick.
    public mutating func add(linesX: Double, linesY: Double, at time: TimeInterval) {
        let reversed = (linesY != 0 && pendingY != 0 && (linesY > 0) != (pendingY > 0))
            || (linesX != 0 && pendingX != 0 && (linesX > 0) != (pendingX > 0))
        if reversed {
            // A change of direction stops the glide instead of fighting it.
            pendingX = 0
            pendingY = 0
            streak = 0
        }
        streak = time - lastTick < 0.08 ? min(streak + 1, 8) : 0
        lastTick = time
        let boost = 1 + Double(streak) * 0.25
        pendingX += linesX * Self.pixelsPerLine * speed * boost
        pendingY += linesY * Self.pixelsPerLine * speed * boost
    }

    /// Advances the glide by `dt` seconds and returns whole pixels to scroll.
    public mutating func step(dt: Double) -> (x: Int, y: Int) {
        guard !isIdle else {
            stop()
            return (0, 0)
        }
        let fraction = 1 - exp(-max(dt, 0) / max(smoothness, 0.01))
        var moveX = pendingX * fraction
        var moveY = pendingY * fraction
        if abs(pendingX - moveX) < 0.5 { moveX = pendingX }
        if abs(pendingY - moveY) < 0.5 { moveY = pendingY }
        pendingX -= moveX
        pendingY -= moveY
        // Carry the fractional part so small glides don't lose distance.
        let totalX = moveX + carryX
        let totalY = moveY + carryY
        let wholeX = totalX.rounded(.towardZero)
        let wholeY = totalY.rounded(.towardZero)
        carryX = totalX - wholeX
        carryY = totalY - wholeY
        return (Int(wholeX), Int(wholeY))
    }

    public mutating func stop() {
        pendingX = 0
        pendingY = 0
        carryX = 0
        carryY = 0
        streak = 0
    }
}
