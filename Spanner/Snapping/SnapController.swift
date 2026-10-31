import AppKit
import Observation
import SpannerCore

/// Moves windows into halves, quarters, thirds and custom grid cells, from
/// keyboard shortcuts or by dragging a window to a screen edge. Each display
/// has its own gap and grid (`DisplaySnapRule`).
///
/// Public Accessibility only: windows are moved with AXUIElement, and drags
/// are watched with a listen-only event tap. Both need Accessibility.
@Observable
final class SnapController {
    enum Status: Equatable {
        case disabled, needsPermission, ready
    }

    let permissions: PermissionsManager
    let settings = SnapSettings()
    private(set) var status: Status = .disabled
    /// Actions whose shortcut another app already holds.
    private(set) var unavailableShortcuts: Set<SnapAction> = []
    /// macOS's own "drag windows to screen edges to tile" setting, which
    /// fights drag snapping when both are on.
    private(set) var nativeEdgeTilingEnabled = false

    @ObservationIgnored private let hotkeys: HotkeyCenter
    @ObservationIgnored private var registeredHotkeys: [UInt32] = []
    @ObservationIgnored private var registeredShortcuts: [SnapAction: KeyShortcut]?
    @ObservationIgnored private lazy var dragTap = EventTap { [unowned self] type, event in
        handleDrag(type, event)
        return .pass
    }
    @ObservationIgnored private let preview = SnapPreviewPanel()
    /// Frames from before a window was first snapped, for Restore.
    @ObservationIgnored private var restoreFrames: [CGWindowID: CGRect] = [:]
    @ObservationIgnored private var drag: DragState?
    @ObservationIgnored private var isStarted = false

    /// Tracks one left-button drag that might be moving a window.
    private struct DragState {
        let start: CGPoint
        var window: AXUIElement?
        var initialFrame: CGRect?
        var lookedUp = false
        var isMovingWindow = false
        var lastCheck: TimeInterval = 0
        var gridAnchor: SnapGrid.Cell?
        var target: CGRect?
    }

    init(permissions: PermissionsManager, hotkeys: HotkeyCenter) {
        self.permissions = permissions
        self.hotkeys = hotkeys
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshNativeTiling()
        reconcile()
        observeChanges()
    }

    func stop() {
        isStarted = false
        endDrag()
        dragTap.remove()
        unregisterHotkeys()
    }

    func refreshNativeTiling() {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        // Missing means the default, which is on (macOS 15+).
        nativeEdgeTilingEnabled = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, domain) as? Bool ?? true
    }

    func openDesktopAndDockSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    // MARK: - Configuration

    private func observeChanges() {
        withObservationTracking {
            _ = permissions.accessibilityGranted
            _ = settings.isEnabled
            _ = settings.dragSnapping
            _ = settings.activeShortcuts
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.reconcile()
                self.observeChanges()
            }
        }
    }

    private func reconcile() {
        guard settings.isEnabled else {
            status = .disabled
            teardown()
            return
        }
        guard permissions.accessibilityGranted else {
            status = .needsPermission
            teardown()
            return
        }
        status = .ready
        let shortcuts = Dictionary(uniqueKeysWithValues: settings.activeShortcuts)
        if shortcuts != registeredShortcuts {
            unregisterHotkeys()
            registerHotkeys(shortcuts)
        }
        if settings.dragSnapping {
            dragTap.install(events: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], listenOnly: true)
        } else {
            endDrag()
            dragTap.remove()
        }
    }

    private func teardown() {
        endDrag()
        dragTap.remove()
        unregisterHotkeys()
    }

    private func registerHotkeys(_ shortcuts: [SnapAction: KeyShortcut]) {
        var unavailable: Set<SnapAction> = []
        for (action, shortcut) in shortcuts {
            if let id = hotkeys.register(shortcut, handler: { [weak self] in self?.perform(action) }) {
                registeredHotkeys.append(id)
            } else {
                unavailable.insert(action)
            }
        }
        unavailableShortcuts = unavailable
        registeredShortcuts = shortcuts
    }

    private func unregisterHotkeys() {
        hotkeys.unregister(registeredHotkeys)
        registeredHotkeys = []
        registeredShortcuts = nil
        unavailableShortcuts = []
    }

    // MARK: - Actions

    /// Snaps the focused window.
    func perform(_ action: SnapAction) {
        guard let window = WindowMover.focusedWindow(), let current = WindowMover.frame(of: window),
              let screen = NSScreen.screen(forAX: current) else {
            NSSound.beep()
            return
        }
        let id = WindowMover.windowID(of: window)
        switch action {
        case .restore:
            guard let id, let original = restoreFrames.removeValue(forKey: id) else { return }
            WindowMover.setFrame(original, of: window)
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { $0.axFrame.minX < $1.axFrame.minX }
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return }
            let offset = action == .nextDisplay ? 1 : screens.count - 1
            let destination = screens[(index + offset) % screens.count]
            WindowMover.setFrame(SnapGeometry.map(current, from: screen.axVisibleFrame, to: destination.axVisibleFrame),
                                 of: window)
        default:
            let rule = settings.rule(for: screen.persistentKey)
            guard let frame = SnapGeometry.frame(for: action, in: screen.axVisibleFrame, gap: rule.gap,
                                                 windowSize: current.size) else { return }
            apply(frame, to: window, id: id, from: current)
        }
    }

    private func apply(_ frame: CGRect, to window: AXUIElement, id: CGWindowID?, from current: CGRect) {
        if let id, restoreFrames[id] == nil { restoreFrames[id] = current }
        WindowMover.setFrame(frame, of: window)
    }

    // MARK: - Drag snapping

    private func handleDrag(_ type: CGEventType, _ event: CGEvent) {
        let point = event.location
        switch type {
        case .leftMouseDown:
            drag = DragState(start: point)
        case .leftMouseDragged:
            guard var state = drag else { return }
            updateDrag(&state, at: point, shiftHeld: event.flags.contains(.maskShift))
            drag = state
        case .leftMouseUp:
            if let state = drag, state.isMovingWindow, let target = state.target, let window = state.window,
               let initial = state.initialFrame {
                apply(target, to: window, id: WindowMover.windowID(of: window), from: initial)
            }
            endDrag()
        default:
            break
        }
    }

    private func updateDrag(_ state: inout DragState, at point: CGPoint, shiftHeld: Bool) {
        if !state.lookedUp {
            // Wait for real movement so plain clicks never pay for an AX call.
            guard hypot(point.x - state.start.x, point.y - state.start.y) > 4 else { return }
            state.lookedUp = true
            state.window = WindowMover.window(at: state.start)
            state.initialFrame = state.window.flatMap(WindowMover.frame(of:))
        }
        guard let window = state.window, let initial = state.initialFrame else { return }
        if !state.isMovingWindow {
            // A title-bar drag moves the window without resizing it; anything
            // else (resizing, selecting text, dragging files) is ignored.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - state.lastCheck > 0.05 else { return }
            state.lastCheck = now
            guard let frame = WindowMover.frame(of: window) else { return }
            guard frame.size == initial.size, frame.origin != initial.origin else { return }
            state.isMovingWindow = true
        }

        guard let screen = NSScreen.screen(containingAX: point) else { return }
        let rule = settings.rule(for: screen.persistentKey)
        let visible = screen.axVisibleFrame
        var target: CGRect?
        if shiftHeld {
            // Hold Shift to snap to the grid; moving while holding it spans
            // cells from where Shift went down.
            let cell = rule.grid.cell(at: point, in: visible)
            let anchor = state.gridAnchor ?? cell
            state.gridAnchor = anchor
            target = rule.grid.frame(from: anchor, to: cell, in: visible, gap: rule.gap)
        } else {
            state.gridAnchor = nil
            if rule.edgeSnapping, let action = SnapZone.action(at: point, screen: screen.axFrame) {
                target = SnapGeometry.frame(for: action, in: visible, gap: rule.gap, windowSize: initial.size)
            }
        }
        state.target = target
        if let target {
            preview.show(axFrame: target)
        } else {
            preview.hide()
        }
    }

    private func endDrag() {
        drag = nil
        preview.hide()
    }
}
