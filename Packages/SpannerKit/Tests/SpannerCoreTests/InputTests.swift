import Foundation
import Testing
@testable import SpannerCore

@Suite("Key shortcuts")
struct KeyShortcutTests {
    @Test func keycapsFollowMacOSModifierOrder() {
        let all = KeyShortcut.Modifier.all
        #expect(KeyShortcut(keyCode: 0x2E, modifiers: all).keycaps == ["⌃", "⌥", "⇧", "⌘", "M"])
        #expect(KeyShortcut(keyCode: 0x7B, modifiers: KeyShortcut.Modifier.option).displayString == "⌥←")
    }

    @Test func plainKeysAndShiftOnlyAreRejected() {
        #expect(!KeyShortcut(keyCode: 0x00, modifiers: 0).isValid)
        #expect(!KeyShortcut(keyCode: 0x00, modifiers: KeyShortcut.Modifier.shift).isValid)
        #expect(KeyShortcut(keyCode: 0x00, modifiers: KeyShortcut.Modifier.control).isValid)
        // Function keys don't collide with typing, so they may stand alone.
        #expect(KeyShortcut(keyCode: 0x69, modifiers: 0).isValid)
    }

    @Test func cocoaFlagsConvertToCarbon() {
        let cocoa: UInt = (1 << 20) | (1 << 19) // command + option
        #expect(KeyShortcut.carbonModifiers(fromCocoa: cocoa)
                    == KeyShortcut.Modifier.command | KeyShortcut.Modifier.option)
        #expect(KeyShortcut.carbonModifiers(fromCocoa: 1 << 16) == 0) // caps lock is ignored
    }

    @Test func unknownKeysStillHaveAName() {
        #expect(KeyShortcut.keyName(0xFF) == "Key 255")
    }

    @Test func roundTripsThroughJSON() throws {
        let shortcut = KeyShortcut(keyCode: 0x2E, modifiers: KeyShortcut.Modifier.control)
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyShortcut.self, from: data)
        #expect(decoded == shortcut)
    }
}

@Suite("Mouse scrolling")
struct MouseScrollTests {
    @Test func trackpadEventsAreNeverInverted() {
        for direction in MouseScrollDirection.allCases {
            #expect(!direction.invertsWheel(isContinuous: true, systemNatural: true))
            #expect(!direction.invertsWheel(isContinuous: true, systemNatural: false))
        }
    }

    @Test func wheelIsInvertedOnlyWhenItDisagreesWithTheSystem() {
        #expect(MouseScrollDirection.standard.invertsWheel(isContinuous: false, systemNatural: true))
        #expect(!MouseScrollDirection.standard.invertsWheel(isContinuous: false, systemNatural: false))
        #expect(MouseScrollDirection.natural.invertsWheel(isContinuous: false, systemNatural: false))
        #expect(!MouseScrollDirection.natural.invertsWheel(isContinuous: false, systemNatural: true))
        #expect(!MouseScrollDirection.followSystem.invertsWheel(isContinuous: false, systemNatural: true))
    }

    @Test func middleButtonCannotMapToMiddleClick() {
        #expect(!MouseButton.middle.choices.contains(.middleClick))
        #expect(MouseButton.back.choices.contains(.middleClick))
    }

    @Test func keystrokeActionsHaveKeys() {
        #expect(MouseButtonAction.back.keystroke?.keyCode == 0x21)
        #expect(MouseButtonAction.passThrough.keystroke == nil)
        #expect(MouseButtonAction.middleClick.keystroke == nil)
    }
}

@Suite("Smooth scroller")
struct SmoothScrollerTests {
    /// Runs the glide to completion at 120 Hz and sums what it scrolled.
    func drain(_ scroller: inout SmoothScroller) -> (x: Int, y: Int, steps: Int) {
        var x = 0, y = 0, steps = 0
        while !scroller.isIdle && steps < 10_000 {
            let step = scroller.step(dt: 1.0 / 120)
            x += step.x
            y += step.y
            steps += 1
        }
        return (x, y, steps)
    }

    @Test func oneTickScrollsItsFullDistance() {
        var scroller = SmoothScroller(speed: 1, smoothness: 0.09)
        scroller.add(linesX: 0, linesY: -1, at: 0)
        let result = drain(&scroller)
        #expect(abs(result.y + Int(SmoothScroller.pixelsPerLine)) <= 1)
        #expect(result.x == 0)
        #expect(result.steps > 5) // spread over several frames, not one jump
    }

    @Test func rapidTicksAccelerate() {
        var slow = SmoothScroller()
        slow.add(linesX: 0, linesY: 1, at: 0)
        slow.add(linesX: 0, linesY: 1, at: 1)
        var fast = SmoothScroller()
        fast.add(linesX: 0, linesY: 1, at: 0)
        fast.add(linesX: 0, linesY: 1, at: 0.02)
        #expect(fast.pendingY > slow.pendingY)
    }

    @Test func reversingDirectionCancelsTheGlide() {
        var scroller = SmoothScroller()
        scroller.add(linesX: 0, linesY: 3, at: 0)
        scroller.add(linesX: 0, linesY: -1, at: 0.5)
        #expect(scroller.pendingY < 0)
        #expect(scroller.pendingY == -SmoothScroller.pixelsPerLine)
    }

    @Test func idleScrollerReturnsNothing() {
        var scroller = SmoothScroller()
        #expect(scroller.isIdle)
        #expect(scroller.step(dt: 0.1) == (0, 0))
    }
}
