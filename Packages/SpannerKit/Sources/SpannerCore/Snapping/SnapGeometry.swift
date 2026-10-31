import CoreGraphics
import Foundation

/// A place a window can be snapped to. Rectangle's default shortcuts are
/// used as defaults, since they are what most people already know.
public enum SnapAction: String, CaseIterable, Identifiable, Sendable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, restore
    case nextDisplay, previousDisplay

    public var id: Self { self }

    public var title: String {
        switch self {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .leftThird: "First third"
        case .centerThird: "Center third"
        case .rightThird: "Last third"
        case .leftTwoThirds: "First two thirds"
        case .rightTwoThirds: "Last two thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        case .restore: "Restore"
        case .nextDisplay: "Next display"
        case .previousDisplay: "Previous display"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .leftThird, .leftTwoThirds: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird, .rightTwoThirds: "rectangle.trailingthird.inset.filled"
        case .maximize: "rectangle.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .restore: "arrow.uturn.backward"
        case .nextDisplay: "rectangle.portrait.and.arrow.right"
        case .previousDisplay: "rectangle.portrait.and.arrow.forward"
        }
    }

    /// Default shortcut: ⌃⌥ plus a key, ⌃⌥⌘ arrows for displays.
    public var defaultShortcut: KeyShortcut? {
        let ctrlOpt = KeyShortcut.Modifier.control | KeyShortcut.Modifier.option
        let key: UInt32? = switch self {
        case .leftHalf: 0x7B
        case .rightHalf: 0x7C
        case .topHalf: 0x7E
        case .bottomHalf: 0x7D
        case .topLeft: 0x20 // U
        case .topRight: 0x22 // I
        case .bottomLeft: 0x26 // J
        case .bottomRight: 0x28 // K
        case .leftThird: 0x02 // D
        case .centerThird: 0x03 // F
        case .rightThird: 0x05 // G
        case .leftTwoThirds: 0x0E // E
        case .rightTwoThirds: 0x11 // T
        case .maximize: 0x24 // Return
        case .center: 0x08 // C
        case .restore: 0x33 // Delete
        case .nextDisplay, .previousDisplay: nil
        }
        if let key { return KeyShortcut(keyCode: key, modifiers: ctrlOpt) }
        switch self {
        case .nextDisplay: return KeyShortcut(keyCode: 0x7C, modifiers: ctrlOpt | KeyShortcut.Modifier.command)
        case .previousDisplay: return KeyShortcut(keyCode: 0x7B, modifiers: ctrlOpt | KeyShortcut.Modifier.command)
        default: return nil
        }
    }

    /// The region as fractions of the screen (x0, x1, y0, y1, top-left
    /// origin), for actions that are a fixed region.
    var region: (x0: Double, x1: Double, y0: Double, y1: Double)? {
        switch self {
        case .leftHalf: (0, 0.5, 0, 1)
        case .rightHalf: (0.5, 1, 0, 1)
        case .topHalf: (0, 1, 0, 0.5)
        case .bottomHalf: (0, 1, 0.5, 1)
        case .topLeft: (0, 0.5, 0, 0.5)
        case .topRight: (0.5, 1, 0, 0.5)
        case .bottomLeft: (0, 0.5, 0.5, 1)
        case .bottomRight: (0.5, 1, 0.5, 1)
        case .leftThird: (0, 1.0 / 3, 0, 1)
        case .centerThird: (1.0 / 3, 2.0 / 3, 0, 1)
        case .rightThird: (2.0 / 3, 1, 0, 1)
        case .leftTwoThirds: (0, 2.0 / 3, 0, 1)
        case .rightTwoThirds: (1.0 / 3, 1, 0, 1)
        case .maximize: (0, 1, 0, 1)
        case .center, .restore, .nextDisplay, .previousDisplay: nil
        }
    }
}

/// Window geometry for snapping. Every rect here uses the Accessibility
/// coordinate space: origin at the top-left of the primary screen, y down.
public enum SnapGeometry {
    /// Frame for `action` inside `visible` (the screen minus menu bar and
    /// Dock), with `gap` points around and between windows. Nil for actions
    /// the controller resolves itself (restore, display moves).
    public static func frame(for action: SnapAction, in visible: CGRect, gap: Double,
                             windowSize: CGSize) -> CGRect? {
        if let r = action.region {
            return region(x0: r.x0, x1: r.x1, y0: r.y0, y1: r.y1, in: visible, gap: gap)
        }
        guard action == .center else { return nil }
        let usable = visible.insetBy(dx: gap, dy: gap)
        let size = CGSize(width: min(windowSize.width, usable.width), height: min(windowSize.height, usable.height))
        return CGRect(x: (usable.midX - size.width / 2).rounded(), y: (usable.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    /// A fractional region of `visible`. Outer edges get the full gap and
    /// inner edges half of it, so two neighbouring windows sit one gap apart.
    public static func region(x0: Double, x1: Double, y0: Double, y1: Double,
                              in visible: CGRect, gap: Double) -> CGRect {
        let usable = visible.insetBy(dx: gap, dy: gap)
        let half = gap / 2
        let left = usable.minX + x0 * usable.width + (x0 > 0 ? half : 0)
        let right = usable.minX + x1 * usable.width - (x1 < 1 ? half : 0)
        let top = usable.minY + y0 * usable.height + (y0 > 0 ? half : 0)
        let bottom = usable.minY + y1 * usable.height - (y1 < 1 ? half : 0)
        return CGRect(x: left.rounded(), y: top.rounded(),
                      width: (right - left).rounded(), height: (bottom - top).rounded())
    }

    /// Converts a rect between AppKit (bottom-left origin) and Accessibility
    /// (top-left origin) space. The conversion is its own inverse.
    public static func flip(_ rect: CGRect, primaryScreenHeight: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Moves `rect` from one screen to another, keeping its relative
    /// position and size, and clamped to the destination.
    public static func map(_ rect: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return rect }
        let sx = destination.width / source.width
        let sy = destination.height / source.height
        let width = min(rect.width * sx, destination.width)
        let height = min(rect.height * sy, destination.height)
        var x = destination.minX + (rect.minX - source.minX) * sx
        var y = destination.minY + (rect.minY - source.minY) * sy
        x = min(max(x, destination.minX), destination.maxX - width)
        y = min(max(y, destination.minY), destination.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// A screen divided into equal cells, for drag-to-grid snapping.
public struct SnapGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    public struct Cell: Hashable, Sendable {
        public let column: Int
        public let row: Int

        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }
    }

    /// The cell under `point`, clamped to the grid.
    public func cell(at point: CGPoint, in visible: CGRect) -> Cell {
        guard visible.width > 0, visible.height > 0 else { return Cell(column: 0, row: 0) }
        let column = Int(((point.x - visible.minX) / visible.width * Double(columns)).rounded(.down))
        let row = Int(((point.y - visible.minY) / visible.height * Double(rows)).rounded(.down))
        return Cell(column: min(max(column, 0), columns - 1), row: min(max(row, 0), rows - 1))
    }

    /// Frame covering every cell between `a` and `b`, inclusive.
    public func frame(from a: Cell, to b: Cell, in visible: CGRect, gap: Double) -> CGRect {
        let c0 = min(a.column, b.column), c1 = max(a.column, b.column) + 1
        let r0 = min(a.row, b.row), r1 = max(a.row, b.row) + 1
        return SnapGeometry.region(x0: Double(c0) / Double(columns), x1: Double(c1) / Double(columns),
                                   y0: Double(r0) / Double(rows), y1: Double(r1) / Double(rows),
                                   in: visible, gap: gap)
    }
}

/// Screen-edge zones for drag snapping: drag a window's title bar to an
/// edge or corner and drop it there.
public enum SnapZone {
    /// The action for a pointer at `point` on a screen whose full frame is
    /// `screen` (corners win over edges). Nil away from the edges.
    public static func action(at point: CGPoint, screen: CGRect, edge: Double = 5, corner: Double = 60) -> SnapAction? {
        let nearLeft = point.x <= screen.minX + edge
        let nearRight = point.x >= screen.maxX - edge - 1
        let nearTop = point.y <= screen.minY + edge
        let nearBottom = point.y >= screen.maxY - edge - 1
        let inTopBand = point.y <= screen.minY + corner
        let inBottomBand = point.y >= screen.maxY - corner
        let inLeftBand = point.x <= screen.minX + corner
        let inRightBand = point.x >= screen.maxX - corner

        if (nearLeft && inTopBand) || (nearTop && inLeftBand) { return .topLeft }
        if (nearRight && inTopBand) || (nearTop && inRightBand) { return .topRight }
        if (nearLeft && inBottomBand) || (nearBottom && inLeftBand) { return .bottomLeft }
        if (nearRight && inBottomBand) || (nearBottom && inRightBand) { return .bottomRight }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearTop { return .maximize }
        return nil
    }
}

/// Snapping rules for one display, chosen in settings.
public struct DisplaySnapRule: Codable, Equatable, Sendable {
    /// Space around and between snapped windows, in points (0...40).
    public var gap: Double
    public var gridColumns: Int
    public var gridRows: Int
    /// Whether dragging a window to this display's edges snaps it.
    public var edgeSnapping: Bool

    public init(gap: Double = 0, gridColumns: Int = 6, gridRows: Int = 4, edgeSnapping: Bool = true) {
        self.gap = gap
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.edgeSnapping = edgeSnapping
    }

    public var grid: SnapGrid { SnapGrid(columns: gridColumns, rows: gridRows) }

    public static let gapRange: ClosedRange<Double> = 0...40
    public static let gridRange: ClosedRange<Int> = 1...12
}
