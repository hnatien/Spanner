import AppKit
import Observation
import SpannerCore

/// State of one open switcher: the windows, the selection, and thumbnails as
/// they arrive. Lives from the shortcut press to the modifier release.
@Observable
final class SwitcherSession: Identifiable {
    enum Mode: Equatable {
        case allWindows
        case currentApp(name: String)
    }

    let id = UUID()
    let mode: Mode
    let trigger: SwitcherTrigger
    let metrics: OverlayMetrics
    private(set) var windows: [SwitcherWindow]
    private(set) var selection: GridSelection
    var thumbnails: [CGWindowID: NSImage] = [:]
    var hoveredID: CGWindowID?
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]
    @ObservationIgnored private let iconProvider: (pid_t) -> NSImage

    init(mode: Mode, trigger: SwitcherTrigger, windows: [SwitcherWindow], metrics: OverlayMetrics, columns: Int,
         iconProvider: @escaping (pid_t) -> NSImage) {
        self.mode = mode
        self.trigger = trigger
        self.windows = windows
        self.metrics = metrics
        self.iconProvider = iconProvider
        selection = GridSelection(count: windows.count, columns: columns)
    }

    var selectedWindow: SwitcherWindow? {
        windows.indices.contains(selection.index) ? windows[selection.index] : nil
    }

    var columns: Int { selection.columns }

    func icon(for pid: pid_t) -> NSImage {
        if let icon = icons[pid] { return icon }
        let icon = iconProvider(pid)
        icons[pid] = icon
        return icon
    }

    func next() { selection.next() }
    func previous() { selection.previous() }
    func move(_ direction: GridSelection.Direction) { selection.move(direction) }

    func select(_ id: CGWindowID) {
        if let index = windows.firstIndex(where: { $0.id == id }) { selection.select(index) }
    }

    /// Replaces the list (fresher Accessibility data arrived) while keeping
    /// the same window selected.
    func update(windows newWindows: [SwitcherWindow], columns: Int) {
        let selectedID = selectedWindow?.id
        windows = newWindows
        let index = selectedID.flatMap { id in newWindows.firstIndex { $0.id == id } }
        selection.update(count: newWindows.count, columns: columns, index: index)
    }
}

/// Sizes for the overlay, shared by the panel (to size its window) and the
/// SwiftUI view (to lay out tiles) so both always agree.
struct OverlayMetrics: Equatable {
    let tileWidth: CGFloat

    static let cellPadding: CGFloat = 10
    static let titleSpacing: CGFloat = 8
    static let titleHeight: CGFloat = 18
    static let gridSpacing: CGFloat = 6
    static let outerPadding: CGFloat = 18
    static let cornerRadius: CGFloat = 26
    /// Transparent margin around the overlay so its shadow isn't clipped.
    static let shadowMargin: CGFloat = 40

    var thumbnailHeight: CGFloat { (tileWidth * 0.625).rounded() }
    var cellWidth: CGFloat { tileWidth + Self.cellPadding * 2 }
    var cellHeight: CGFloat { thumbnailHeight + Self.titleSpacing + Self.titleHeight + Self.cellPadding * 2 }

    func columns(count: Int, screenWidth: CGFloat) -> Int {
        SwitcherGridLayout.columns(count: count,
                                   availableWidth: Double(screenWidth * 0.8 - Self.outerPadding * 2),
                                   cellWidth: Double(cellWidth), spacing: Double(Self.gridSpacing))
    }

    /// Size of the visible overlay (without the shadow margin).
    func contentSize(count: Int, columns: Int, screenHeight: CGFloat) -> CGSize {
        guard count > 0 else { return CGSize(width: 380, height: 190) }
        let rows = CGFloat((count + columns - 1) / columns)
        let gridWidth = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * Self.gridSpacing
        let gridHeight = rows * cellHeight + (rows - 1) * Self.gridSpacing
        let maxGridHeight = screenHeight * 0.8 - Self.outerPadding * 2
        return CGSize(width: gridWidth + Self.outerPadding * 2,
                      height: min(gridHeight, maxGridHeight) + Self.outerPadding * 2)
    }

    /// How many tiles fit without scrolling; these get thumbnails first.
    func visibleCount(columns: Int, contentHeight: CGFloat) -> Int {
        let gridHeight = contentHeight - Self.outerPadding * 2
        let rows = Int(((gridHeight + Self.gridSpacing) / (cellHeight + Self.gridSpacing)).rounded(.up))
        return max(1, rows) * columns
    }
}
