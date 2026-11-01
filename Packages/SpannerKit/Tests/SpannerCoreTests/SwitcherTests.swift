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
                orderedOut: Bool = false) -> WindowCandidate {
        WindowCandidate(id: id, pid: pid, appName: "App", title: title, width: size, height: size, layer: layer,
                        isOnScreen: onScreen, hasAXElement: ax, isMinimized: minimized, isOrderedOut: orderedOut)
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

    @Test func currentAppModeKeepsOnlyThatApp() {
        let candidates = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10, onScreen: false)]
        let list = WindowListBuilder.build(candidates, zOrder: [2, 1], appRecency: [],
                                           options: .init(onlyPID: 10))
        #expect(list.map(\.id) == [1, 3])
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
