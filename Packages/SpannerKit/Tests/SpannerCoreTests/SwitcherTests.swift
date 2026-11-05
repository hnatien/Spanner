import Testing
@testable import SpannerCore

@Suite("System Command-Tab policy")
struct SystemSwitcherPolicyTests {
    @Test func takeoverDisablesAnEnabledShortcut() {
        #expect(SystemSwitcherPolicy.action(wantsTakeover: true, ledgerSaysDisabledByUs: false,
                                            systemShortcutEnabled: true) == .disable)
    }

    @Test func takeoverLeavesAnAlreadyDisabledShortcutAlone() {
        #expect(SystemSwitcherPolicy.action(wantsTakeover: true, ledgerSaysDisabledByUs: true,
                                            systemShortcutEnabled: false) == .none)
        #expect(SystemSwitcherPolicy.action(wantsTakeover: true, ledgerSaysDisabledByUs: false,
                                            systemShortcutEnabled: false) == .none)
    }

    @Test func relaunchAfterCrashRestoresOurDisable() {
        #expect(SystemSwitcherPolicy.action(wantsTakeover: false, ledgerSaysDisabledByUs: true,
                                            systemShortcutEnabled: false) == .restore)
    }

    @Test func staleLedgerIsCleared() {
        #expect(SystemSwitcherPolicy.action(wantsTakeover: false, ledgerSaysDisabledByUs: true,
                                            systemShortcutEnabled: true) == .restore)
    }

    @Test func neverRestoresAShortcutAnotherAppDisabled() {
        #expect(SystemSwitcherPolicy.action(wantsTakeover: false, ledgerSaysDisabledByUs: false,
                                            systemShortcutEnabled: false) == .none)
    }

    @Test func onlyCommandTabReplacesTheSystemSwitcher() {
        #expect(SwitcherTrigger.allCases.filter(\.replacesSystemSwitcher) == [.command])
    }
}

@Suite("Window list")
struct WindowListTests {
    func window(_ id: UInt32, pid: Int32 = 10, title: String = "Doc", size: Double = 500, layer: Int = 0,
                onScreen: Bool = true, ax: Bool = true, minimized: Bool = false,
                orderedOut: Bool = false, behindFullScreen: Bool = false) -> WindowCandidate {
        WindowCandidate(id: id, pid: pid, appName: "App", title: title, width: size, height: size, layer: layer,
                        isOnScreen: onScreen, hasAXElement: ax, isMinimized: minimized, isOrderedOut: orderedOut,
                        isBehindFullScreen: behindFullScreen)
    }

    @Test func closedButRetainedWindowsAreDropped() {
        let candidates = [
            window(1),
            window(2, onScreen: false, ax: false, orderedOut: true),
            window(3, onScreen: false, orderedOut: true),
            window(4, onScreen: false),
            window(5, onScreen: false, minimized: true, orderedOut: true),
        ]
        let list = WindowListBuilder.build(candidates, zOrder: [1], appRecency: [], options: .init())
        #expect(list.map(\.id) == [1, 4, 5])
    }

    @Test func visibleWindowsFollowZOrder() {
        let list = WindowListBuilder.build([window(1), window(2), window(3)], zOrder: [3, 1, 2],
                                           appRecency: [], options: .init())
        #expect(list.map(\.id) == [3, 1, 2])
    }

    @Test func hiddenWindowsComeAfterVisibleOnesByAppRecency() {
        let candidates = [
            window(1, pid: 10, onScreen: false),
            window(2, pid: 20),
            window(3, pid: 30, onScreen: false),
            window(4, pid: 30, onScreen: false, minimized: true),
        ]
        let list = WindowListBuilder.build(candidates, zOrder: [2], appRecency: [30, 10], options: .init())
        #expect(list.map(\.id) == [2, 3, 4, 1])
    }

    @Test func filtersHelperAndNonNormalWindows() {
        let candidates = [
            window(1),
            window(2, title: "", ax: false),        // invisible helper (blank in Phase 0)
            window(3, title: "", ax: true),         // untitled but real
            window(4, layer: 25),                   // menu bar / overlay layer
            window(5, size: 40),                    // too small
            window(1),                              // duplicate ID
        ]
        let list = WindowListBuilder.build(candidates, zOrder: [1, 3], appRecency: [],
                                           options: .init())
        #expect(list.map(\.id) == [1, 3])
    }

    @Test func respectsMinimizedAndOtherSpaceOptions() {
        let candidates = [window(1), window(2, onScreen: false, minimized: true), window(3, onScreen: false)]
        let noMinimized = WindowListBuilder.build(candidates, zOrder: [1], appRecency: [],
                                                  options: .init(includeMinimized: false))
        #expect(noMinimized.map(\.id) == [1, 3])
        let noElsewhere = WindowListBuilder.build(candidates, zOrder: [1], appRecency: [],
                                                  options: .init(includeOtherSpaces: false))
        #expect(noElsewhere.map(\.id) == [1, 2])
    }

    @Test func windowsBehindFullScreenAreNotOnAnotherSpace() {
        let behind = window(2, onScreen: false, behindFullScreen: true)
        #expect(!behind.isElsewhere)
        #expect(window(3, onScreen: false).isElsewhere)
        let list = WindowListBuilder.build([window(1), behind, window(3, onScreen: false)], zOrder: [1],
                                           appRecency: [], options: .init(includeOtherSpaces: false))
        #expect(list.map(\.id) == [1, 2])
    }

    @Test func behindFullScreenStillFallsToTheOrderedOutRule() {
        let closed = window(2, onScreen: false, orderedOut: true, behindFullScreen: true)
        #expect(!WindowListBuilder.isEligible(closed, options: .init()))
        let minimized = window(3, onScreen: false, minimized: true, orderedOut: true)
        #expect(WindowListBuilder.isEligible(minimized, options: .init(includeOtherSpaces: false)))
    }

    @Test func currentAppModeKeepsOnlyThatApp() {
        let candidates = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10, onScreen: false)]
        let list = WindowListBuilder.build(candidates, zOrder: [2, 1], appRecency: [],
                                           options: .init(onlyPID: 10))
        #expect(list.map(\.id) == [1, 3])
    }
}

@Suite("Window placement")
struct WindowPlacementTests {
    func classify(orderedIn: Bool?, spaces: [Int]?, visible: Set<Int> = [1],
                  covered: Set<Int> = []) -> (isOrderedOut: Bool, isBehindFullScreen: Bool) {
        WindowPlacement.classify(isOrderedIn: orderedIn, spaces: { spaces }, visibleSpaces: visible,
                                 coveredDesktops: covered)
    }

    @Test func orderedInWindowOnAnotherSpaceIsKept() {
        let placement = classify(orderedIn: true, spaces: [2])
        #expect(!placement.isOrderedOut && !placement.isBehindFullScreen)
    }

    @Test func windowOnNoSpaceIsOrderedOut() {
        #expect(classify(orderedIn: false, spaces: []).isOrderedOut)
        #expect(classify(orderedIn: nil, spaces: []).isOrderedOut)
    }

    @Test func notOrderedInOnAShownSpaceIsOrderedOut() {
        #expect(classify(orderedIn: false, spaces: [1]).isOrderedOut)
    }

    /// A minimized window on another Space is not ordered in either, and
    /// has no Accessibility element to say it is minimized.
    @Test func notOrderedInOnAnotherSpaceIsKept() {
        #expect(!classify(orderedIn: false, spaces: [2]).isOrderedOut)
    }

    @Test func failedSpacesLookupKeepsTheWindow() {
        #expect(!classify(orderedIn: false, spaces: nil).isOrderedOut)
        #expect(!classify(orderedIn: nil, spaces: nil).isOrderedOut)
    }

    @Test func orderedInOnACoveredDesktopIsBehindFullScreen() {
        let placement = classify(orderedIn: true, spaces: [2], visible: [200], covered: [2])
        #expect(!placement.isOrderedOut && placement.isBehindFullScreen)
    }

    @Test func notOrderedInOnACoveredDesktopIsElsewhere() {
        let placement = classify(orderedIn: false, spaces: [2], visible: [200], covered: [2])
        #expect(!placement.isOrderedOut && !placement.isBehindFullScreen)
    }

    @Test func spacesAreNotReadForAnOrderedInWindowWithNothingCovered() {
        var reads = 0
        _ = WindowPlacement.classify(isOrderedIn: true, spaces: { reads += 1; return [2] }, visibleSpaces: [1],
                                     coveredDesktops: [])
        #expect(reads == 0)
    }
}

@Suite("Desktop under full screen")
struct DesktopMemoryTests {
    let display = "main"

    @Test func onlyDesktopIsCoveredByFullScreen() {
        let memory = DesktopMemory()
        #expect(memory.coveredDesktops([.init(display: display, current: 200, desktops: [1])]) == [1])
    }

    @Test func showingADesktopCoversNothing() {
        var memory = DesktopMemory()
        let spaces = [DisplaySpaces(display: display, current: 1, desktops: [1, 2])]
        memory.note(spaces)
        #expect(memory.coveredDesktops(spaces).isEmpty)
    }

    @Test func remembersTheDesktopLastShown() {
        var memory = DesktopMemory()
        memory.note([.init(display: display, current: 2, desktops: [1, 2])])
        let fullScreen = [DisplaySpaces(display: display, current: 200, desktops: [1, 2])]
        memory.note(fullScreen)
        #expect(memory.coveredDesktops(fullScreen) == [2])
    }

    @Test func unknownDesktopAmongSeveralIsLeftOut() {
        let memory = DesktopMemory()
        #expect(memory.coveredDesktops([.init(display: display, current: 200, desktops: [1, 2])]).isEmpty)
    }

    @Test func forgetsARemovedDesktop() {
        var memory = DesktopMemory()
        memory.note([.init(display: display, current: 3, desktops: [1, 3])])
        #expect(memory.coveredDesktops([.init(display: display, current: 200, desktops: [1])]) == [1])
    }

    @Test func forgetsADetachedDisplay() {
        var memory = DesktopMemory()
        memory.note([.init(display: "a", current: 2, desktops: [1, 2]),
                     .init(display: "b", current: 5, desktops: [4, 5])])
        memory.note([.init(display: "a", current: 2, desktops: [1, 2])])
        #expect(memory.coveredDesktops([.init(display: "b", current: 200, desktops: [4, 5])]).isEmpty)
    }

    @Test func eachDisplayKeepsItsOwnDesktop() {
        var memory = DesktopMemory()
        memory.note([.init(display: "a", current: 2, desktops: [1, 2]),
                     .init(display: "b", current: 5, desktops: [4, 5])])
        let spaces = [DisplaySpaces(display: "a", current: 200, desktops: [1, 2]),
                      DisplaySpaces(display: "b", current: 5, desktops: [4, 5])]
        #expect(memory.coveredDesktops(spaces) == [2])
    }
}

@Suite("Grid selection")
struct GridSelectionTests {
    @Test func startsOnThePreviousWindow() {
        #expect(GridSelection(count: 5, columns: 3).index == 1)
        #expect(GridSelection(count: 1, columns: 3).index == 0)
        #expect(GridSelection(count: 0, columns: 3).index == 0)
    }

    @Test func tabWrapsBothWays() {
        var selection = GridSelection(count: 3, columns: 3, index: 2)
        selection.next()
        #expect(selection.index == 0)
        selection.previous()
        #expect(selection.index == 2)
    }

    @Test func downWrapsToTheTopOfTheColumn() {
        // 0 1 2
        // 3 4
        var selection = GridSelection(count: 5, columns: 3, index: 1)
        selection.move(.down)
        #expect(selection.index == 4)
        selection.move(.down)
        #expect(selection.index == 1)
        selection.select(2)
        selection.move(.down)          // no item below 2
        #expect(selection.index == 2)
    }

    @Test func upWrapsToTheLastRowThatHasTheColumn() {
        var selection = GridSelection(count: 5, columns: 3, index: 0)
        selection.move(.up)
        #expect(selection.index == 3)
        selection.select(2)
        selection.move(.up)            // last row has no column 2
        #expect(selection.index == 2)
    }

    @Test func updateClampsToNewCount() {
        var selection = GridSelection(count: 6, columns: 3, index: 5)
        selection.update(count: 2, columns: 2)
        #expect(selection.index == 1)
        selection.update(count: 0, columns: 2)
        #expect(selection.index == 0)
        selection.next()
        #expect(selection.index == 0)
    }

    @Test func layoutBalancesRows() {
        #expect(SwitcherGridLayout.columns(count: 7, availableWidth: 1200, cellWidth: 220, spacing: 10) == 4)
        #expect(SwitcherGridLayout.columns(count: 3, availableWidth: 1200, cellWidth: 220, spacing: 10) == 3)
        #expect(SwitcherGridLayout.columns(count: 10, availableWidth: 100, cellWidth: 220, spacing: 10) == 1)
        #expect(SwitcherGridLayout.columns(count: 0, availableWidth: 1200, cellWidth: 220, spacing: 10) == 1)
    }
}

@Suite("Rival switchers")
struct RivalSwitchersTests {
    @Test func findsAltTabAmongRunningApps() {
        let running = ["com.apple.finder", "com.lwouis.alt-tab-macos", "com.apple.Safari"]
        #expect(RivalSwitchers.running(in: running) == ["AltTab"])
    }

    @Test func reportsEachSwitcherOnceEvenWithSeveralProcesses() {
        let running = ["com.manytricks.Witch", "com.manytricks.WitchDaemon", "com.lwouis.alt-tab-macos"]
        #expect(RivalSwitchers.running(in: running) == ["AltTab", "Witch"])
    }

    @Test func isEmptyWhenNoneAreRunning() {
        #expect(RivalSwitchers.running(in: ["com.apple.finder"]).isEmpty)
        #expect(RivalSwitchers.running(in: [String]()).isEmpty)
    }
}
