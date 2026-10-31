import CoreGraphics
import Foundation
import Testing
@testable import SpannerCore

@Suite("Snap geometry")
struct SnapGeometryTests {
    let visible = CGRect(x: 0, y: 25, width: 1000, height: 600)
    let window = CGSize(width: 400, height: 300)

    @Test func halvesSplitTheVisibleFrame() {
        #expect(SnapGeometry.frame(for: .leftHalf, in: visible, gap: 0, windowSize: window)
                    == CGRect(x: 0, y: 25, width: 500, height: 600))
        #expect(SnapGeometry.frame(for: .bottomHalf, in: visible, gap: 0, windowSize: window)
                    == CGRect(x: 0, y: 325, width: 1000, height: 300))
    }

    @Test func gapsAreFullOutsideAndHalfBetween() {
        let left = SnapGeometry.frame(for: .leftHalf, in: visible, gap: 10, windowSize: window)!
        let right = SnapGeometry.frame(for: .rightHalf, in: visible, gap: 10, windowSize: window)!
        #expect(left.minX == 10)
        #expect(left.minY == 35)
        #expect(right.maxX == 990)
        #expect(right.minX - left.maxX == 10)
        #expect(left.height == 580)
    }

    @Test func thirdsTileWithoutOverlap() {
        let a = SnapGeometry.frame(for: .leftThird, in: visible, gap: 0, windowSize: window)!
        let b = SnapGeometry.frame(for: .centerThird, in: visible, gap: 0, windowSize: window)!
        let c = SnapGeometry.frame(for: .rightThird, in: visible, gap: 0, windowSize: window)!
        #expect(abs(a.maxX - b.minX) <= 1)
        #expect(abs(b.maxX - c.minX) <= 1)
        #expect(c.maxX == 1000)
    }

    @Test func centerKeepsSizeButClampsToTheScreen() {
        let centered = SnapGeometry.frame(for: .center, in: visible, gap: 0, windowSize: window)!
        #expect(centered == CGRect(x: 300, y: 175, width: 400, height: 300))
        let huge = SnapGeometry.frame(for: .center, in: visible, gap: 0, windowSize: CGSize(width: 3000, height: 3000))!
        #expect(huge == visible)
    }

    @Test func controllerResolvedActionsHaveNoFrame() {
        for action in [SnapAction.restore, .nextDisplay, .previousDisplay] {
            #expect(SnapGeometry.frame(for: action, in: visible, gap: 0, windowSize: window) == nil)
        }
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flipped = SnapGeometry.flip(rect, primaryScreenHeight: 900)
        #expect(flipped == CGRect(x: 10, y: 680, width: 300, height: 200))
        #expect(SnapGeometry.flip(flipped, primaryScreenHeight: 900) == rect)
    }

    @Test func mapKeepsRelativePlacementAcrossScreens() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let destination = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let moved = SnapGeometry.map(CGRect(x: 500, y: 0, width: 500, height: 250), from: source, to: destination)
        #expect(moved == CGRect(x: 2000, y: 0, width: 1000, height: 500))
    }

    @Test func everyActionWithAShortcutHasAUniqueOne() {
        let shortcuts = SnapAction.allCases.compactMap(\.defaultShortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
        #expect(shortcuts.allSatisfy { $0.isValid })
    }
}

@Suite("Snap grid and zones")
struct SnapGridTests {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)

    @Test func pointMapsToItsCellAndClamps() {
        let grid = SnapGrid(columns: 6, rows: 4)
        #expect(grid.cell(at: CGPoint(x: 250, y: 250), in: visible) == .init(column: 1, row: 1))
        #expect(grid.cell(at: CGPoint(x: 5000, y: -10), in: visible) == .init(column: 5, row: 0))
    }

    @Test func frameSpansCellsInEitherOrder() {
        let grid = SnapGrid(columns: 6, rows: 4)
        let a = grid.frame(from: .init(column: 0, row: 0), to: .init(column: 2, row: 1), in: visible, gap: 0)
        let b = grid.frame(from: .init(column: 2, row: 1), to: .init(column: 0, row: 0), in: visible, gap: 0)
        #expect(a == b)
        #expect(a == CGRect(x: 0, y: 0, width: 600, height: 400))
    }

    @Test func gridDimensionsNeverDropBelowOne() {
        let grid = SnapGrid(columns: 0, rows: -3)
        #expect(grid.columns == 1 && grid.rows == 1)
    }

    @Test func edgesAndCornersPickTheirZones() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        #expect(SnapZone.action(at: CGPoint(x: 0, y: 400), screen: screen) == .leftHalf)
        #expect(SnapZone.action(at: CGPoint(x: 1199, y: 400), screen: screen) == .rightHalf)
        #expect(SnapZone.action(at: CGPoint(x: 600, y: 0), screen: screen) == .maximize)
        #expect(SnapZone.action(at: CGPoint(x: 0, y: 10), screen: screen) == .topLeft)
        #expect(SnapZone.action(at: CGPoint(x: 1190, y: 799), screen: screen) == .bottomRight)
        #expect(SnapZone.action(at: CGPoint(x: 600, y: 799), screen: screen) == nil)
        #expect(SnapZone.action(at: CGPoint(x: 600, y: 400), screen: screen) == nil)
    }

    @Test func zonesWorkOnScreensAwayFromTheOrigin() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        #expect(SnapZone.action(at: CGPoint(x: -1440, y: 300), screen: screen) == .leftHalf)
        #expect(SnapZone.action(at: CGPoint(x: -1, y: 300), screen: screen) == .rightHalf)
    }

    @Test func ruleRoundTripsThroughJSON() throws {
        let rule = DisplaySnapRule(gap: 8, gridColumns: 4, gridRows: 2, edgeSnapping: false)
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(DisplaySnapRule.self, from: data)
        #expect(decoded == rule)
    }
}
