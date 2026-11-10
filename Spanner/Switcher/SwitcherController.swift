import AppKit
import Observation
import SpannerCore
import SwiftUI

/// Windows-style window switcher: hold the modifier, tap Tab to move through
/// every window (with previews), release to switch.
@Observable
final class SwitcherController: FeatureModule {
    enum Status: Equatable {
        case disabled
        /// Accessibility is missing: windows can't be listed by title,
        /// raised, or the modifier release noticed.
        case needsPermission
        case ready
    }

    let permissions: PermissionsManager
    let settings = SwitcherSettings()
    /// Other switchers that may hold the same shortcut.
    let rivals = RivalSwitcherMonitor()
    private(set) var status: Status = .disabled
    /// Set when another app already owns one of the shortcuts.
    private(set) var shortcutUnavailable = false

    var triggerKeycaps: [String] { settings.trigger.keycaps }
    var previewsAvailable: Bool { permissions.screenRecordingGranted }

    @ObservationIgnored private let hotkeys: HotkeyCenter
    @ObservationIgnored private let inventory = WindowInventory()
    @ObservationIgnored private let modifierMonitor = ModifierReleaseMonitor()
    @ObservationIgnored private let capturer = ThumbnailCapturer()
    @ObservationIgnored private let panel = SwitcherPanel()
    @ObservationIgnored private var baseHotkeys: [UInt32] = []
    @ObservationIgnored private var sessionHotkeys: [UInt32] = []
    @ObservationIgnored private var registeredConfig: HotkeyConfig?
    @ObservationIgnored private var session: SwitcherSession?
    @ObservationIgnored private var sessionOptions = WindowListOptions()
    @ObservationIgnored private var sessionScreen: NSScreen?
    @ObservationIgnored private var isRevealed = false
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    /// A change is being waited for. Survives `stop`, so starting again
    /// doesn't add a second wait beside it.
    @ObservationIgnored private var isObserving = false

    private struct HotkeyConfig: Equatable {
        let trigger: SwitcherTrigger
        let appWindows: Bool
    }

    private enum Kind {
        case allWindows, currentApp
    }

    init(permissions: PermissionsManager, hotkeys: HotkeyCenter) {
        self.permissions = permissions
        self.hotkeys = hotkeys
        inventory.onAccessibilityRefresh = { [weak self] in self?.refreshOpenSession() }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        SystemSwitcher.installSignalHandlers()
        inventory.startTracking()
        reconcile()
        observeChanges()
    }

    /// Runs on quit: closes the overlay and hands Command-Tab back to macOS.
    func stop() {
        isStarted = false
        endSession()
        unregisterBaseHotkeys()
        modifierMonitor.removeTap()
        inventory.stopTracking()
        SystemSwitcher.reconcile(wantsTakeover: false)
    }

    // MARK: - Configuration

    private func observeChanges() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = permissions.accessibilityGranted
            _ = settings.isEnabled
            _ = settings.trigger
            _ = settings.appWindowsEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isObserving = false
                guard self.isStarted else { return }
                self.reconcile()
                self.observeChanges()
            }
        }
    }

    /// Brings shortcuts, the event tap and the system Command-Tab in line
    /// with the current settings and permissions.
    private func reconcile() {
        let granted = permissions.accessibilityGranted
        let active = settings.isEnabled && granted
        status = !settings.isEnabled ? .disabled : (granted ? .ready : .needsPermission)

        // Order matters: the system shortcut must be off before a Carbon
        // hotkey for Command-Tab can receive it.
        SystemSwitcher.reconcile(wantsTakeover: active && settings.trigger.replacesSystemSwitcher)

        guard active else {
            endSession()
            unregisterBaseHotkeys()
            modifierMonitor.removeTap()
            return
        }
        modifierMonitor.installTap()
        inventory.refreshAccessibility()
        let config = HotkeyConfig(trigger: settings.trigger, appWindows: settings.appWindowsEnabled)
        if config != registeredConfig {
            unregisterBaseHotkeys()
            registerBaseHotkeys(config)
        }
    }

    private func registerBaseHotkeys(_ config: HotkeyConfig) {
        let modifier = config.trigger.carbonModifier
        var ids: [UInt32?] = [
            hotkeys.register(keyCode: CarbonKey.tab, modifiers: modifier) { [weak self] in self?.handleTrigger(.allWindows) },
        ]
        if config.appWindows {
            ids.append(hotkeys.register(keyCode: CarbonKey.grave, modifiers: modifier) { [weak self] in
                self?.handleTrigger(.currentApp)
            })
        }
        shortcutUnavailable = ids.contains(nil)
        baseHotkeys = ids.compactMap { $0 }
        registeredConfig = config
    }

    private func unregisterBaseHotkeys() {
        hotkeys.unregister(baseHotkeys)
        baseHotkeys = []
        registeredConfig = nil
    }

    // MARK: - Session

    private func handleTrigger(_ kind: Kind) {
        if let session {
            // Repeats of a held Tab arrive here too, so holding Tab cycles.
            session.next()
            return
        }
        beginSession(kind)
    }

    private func beginSession(_ kind: Kind) {
        let trigger = settings.trigger
        var options = WindowListOptions(includeMinimized: settings.includeMinimized,
                                        includeOtherSpaces: settings.includeOtherSpaces)
        var mode = SwitcherSession.Mode.allWindows
        if kind == .currentApp {
            guard let front = NSWorkspace.shared.frontmostApplication else { return }
            options.onlyPID = front.processIdentifier
            mode = .currentApp(name: front.localizedName ?? "")
        }

        let screen = targetScreen()
        let metrics = OverlayMetrics(tileWidth: settings.thumbnailSize.tileWidth)
        let windows = inventory.windows(options: options)
        let session = SwitcherSession(mode: mode, trigger: trigger, windows: windows, metrics: metrics,
                                      columns: metrics.columns(count: windows.count, screenWidth: screen.visibleFrame.width),
                                      iconProvider: { [inventory] in inventory.icon(for: $0) })
        self.session = session
        sessionOptions = options
        sessionScreen = screen
        isRevealed = false
        registerSessionHotkeys(for: trigger)

        // Fires at once if the modifier is already up (a very quick tap),
        // which commits and ends this session before anything is shown.
        modifierMonitor.begin(mask: trigger.eventFlagMask) { [weak self] in self?.commit() }
        guard self.session === session else { return }

        showCachedThumbnails(for: session)
        inventory.refreshAccessibility()
        // A short delay means a quick tap-and-release flips to the previous
        // window without the overlay flashing on screen.
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, self.session === session else { return }
            self.reveal(session)
        }
    }

    private func reveal(_ session: SwitcherSession) {
        guard let screen = sessionScreen else { return }
        isRevealed = true
        let size = contentSize(for: session, on: screen)
        panel.present(SwitcherOverlayView(session: session) { [weak self] id in self?.choose(id) }.id(session.id),
                      contentSize: size, on: screen)
        captureThumbnails(for: session, contentHeight: size.height, scale: screen.backingScaleFactor)
    }

    /// Fresher Accessibility data arrived: rebuild the list in place.
    private func refreshOpenSession() {
        guard let session, let screen = sessionScreen else { return }
        let windows = inventory.windows(options: sessionOptions)
        guard windows != session.windows else { return }
        session.update(windows: windows,
                       columns: session.metrics.columns(count: windows.count, screenWidth: screen.visibleFrame.width))
        if isRevealed {
            panel.resize(contentSize: contentSize(for: session, on: screen), on: screen)
        }
    }

    private func registerSessionHotkeys(for trigger: SwitcherTrigger) {
        let modifier = trigger.carbonModifier
        let bindings: [(UInt32, UInt32, () -> Void)] = [
            (CarbonKey.tab, modifier | CarbonKey.shiftModifier, { [weak self] in self?.session?.previous() }),
            (CarbonKey.leftArrow, modifier, { [weak self] in self?.session?.move(.left) }),
            (CarbonKey.rightArrow, modifier, { [weak self] in self?.session?.move(.right) }),
            (CarbonKey.upArrow, modifier, { [weak self] in self?.session?.move(.up) }),
            (CarbonKey.downArrow, modifier, { [weak self] in self?.session?.move(.down) }),
            (CarbonKey.escape, modifier, { [weak self] in self?.endSession() }),
            (CarbonKey.returnKey, modifier, { [weak self] in self?.commit() }),
        ]
        sessionHotkeys = bindings.compactMap { key, modifiers, action in
            hotkeys.register(keyCode: key, modifiers: modifiers, handler: action)
        }
    }

    private func choose(_ id: CGWindowID) {
        session?.select(id)
        commit()
    }

    private func commit() {
        guard let session else { return }
        let target = session.selectedWindow
        endSession()
        if let target { inventory.focus(target) }
    }

    private func endSession() {
        revealTask?.cancel()
        captureTask?.cancel()
        revealTask = nil
        captureTask = nil
        modifierMonitor.end()
        hotkeys.unregister(sessionHotkeys)
        sessionHotkeys = []
        if isRevealed { panel.dismiss() }
        isRevealed = false
        session = nil
        sessionScreen = nil
    }

    // MARK: - Thumbnails

    private func showCachedThumbnails(for session: SwitcherSession) {
        guard permissions.screenRecordingGranted else { return }
        let ids = session.windows.map(\.id)
        Task { [capturer] in
            let cached = await capturer.cachedImages(for: ids)
            for (id, image) in cached where session.thumbnails[id] == nil {
                session.thumbnails[id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    /// Captures the selected tile first, then the rest of the visible
    /// tiles, then the others, streaming each into the overlay.
    private func captureThumbnails(for session: SwitcherSession, contentHeight: CGFloat, scale: CGFloat) {
        guard permissions.screenRecordingGranted else { return }
        let visible = session.metrics.visibleCount(columns: session.columns, contentHeight: contentHeight)
        var order = session.windows.map(\.id)
        if let selected = session.selectedWindow?.id, let index = order.firstIndex(of: selected), index < visible {
            order.remove(at: index)
            order.insert(selected, at: 0)
        }
        let ids = Array(order.prefix(max(visible, 60)))
        let pixelWidth = Int(session.metrics.tileWidth * scale)
        let live = Set(session.windows.map(\.id))
        let pruneAll = session.mode == .allWindows
        captureTask = Task { [capturer, permissions] in
            if pruneAll { await capturer.prune(keeping: live) }
            let allowed = await capturer.capture(ids, maxPixelWidth: pixelWidth) { id, image in
                guard let image else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    session.thumbnails[id] = NSImage(cgImage: image, size: .zero)
                }
            }
            if !allowed { permissions.noteScreenCaptureRefused() }
        }
    }

    // MARK: - Helpers

    private func targetScreen() -> NSScreen {
        switch settings.overlayScreen {
        case .pointer:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .main:
            return NSScreen.screens.first ?? NSScreen.main!
        }
    }

    private func contentSize(for session: SwitcherSession, on screen: NSScreen) -> CGSize {
        session.metrics.contentSize(count: session.windows.count, columns: session.columns,
                                    screenHeight: screen.visibleFrame.height)
    }
}
