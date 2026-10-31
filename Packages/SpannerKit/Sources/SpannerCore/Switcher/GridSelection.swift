import Foundation

/// Keyboard selection in the switcher grid. Tab and arrows wrap around, the
/// way Windows' Alt-Tab does.
public struct GridSelection: Equatable, Sendable {
    public enum Direction: Sendable {
        case left, right, up, down
    }

    public private(set) var index: Int
    public private(set) var count: Int
    public private(set) var columns: Int

    public init(count: Int, columns: Int, index: Int? = nil) {
        self.count = max(0, count)
        self.columns = max(1, columns)
        self.index = 0
        self.index = clamp(index ?? Self.initialIndex(count: count))
    }

    /// Opening the switcher pre-selects the previous window (index 1), so a
    /// quick tap-and-release flips between the two most recent windows.
    public static func initialIndex(count: Int) -> Int {
        count > 1 ? 1 : 0
    }

    public mutating func next() {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    public mutating func previous() {
        guard count > 0 else { return }
        index = (index - 1 + count) % count
    }

    public mutating func move(_ direction: Direction) {
        guard count > 0 else { return }
        switch direction {
        case .right: next()
        case .left: previous()
        case .down:
            let target = index + columns
            index = target < count ? target : index % columns
        case .up:
            let target = index - columns
            if target >= 0 {
                index = target
            } else {
                // Wrap to the same column in the last row that has it.
                let column = index % columns
                let lastRowStart = ((count - 1) / columns) * columns
                let candidate = lastRowStart + column
                index = candidate < count ? candidate : candidate - columns
            }
        }
    }

    public mutating func select(_ newIndex: Int) {
        index = clamp(newIndex)
    }

    /// Updates the item count (the list can refresh while open), keeping the
    /// selection on the same position where possible.
    public mutating func update(count newCount: Int, columns newColumns: Int, index newIndex: Int? = nil) {
        count = max(0, newCount)
        columns = max(1, newColumns)
        index = clamp(newIndex ?? index)
    }

    private func clamp(_ value: Int) -> Int {
        count == 0 ? 0 : min(max(value, 0), count - 1)
    }
}

/// How many columns the switcher grid uses.
public enum SwitcherGridLayout {
    /// Fits as many columns as the width allows, then rebalances so rows are
    /// as even as possible (7 windows in a 5-wide space become 4 + 3, not 5 + 2).
    public static func columns(count: Int, availableWidth: Double, cellWidth: Double, spacing: Double) -> Int {
        guard count > 0, cellWidth > 0 else { return 1 }
        let fit = Int((availableWidth + spacing) / (cellWidth + spacing))
        let maxColumns = max(1, min(count, fit))
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }
}
