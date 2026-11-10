import AppKit
import Observation
import SpannerCore

/// Mouse fixes macOS lacks: a wheel scroll direction separate from the
/// trackpad, smooth scrolling for notchy wheels, and extra-button actions.
///
/// Works through one active session event tap, which needs Accessibility.
/// Trackpads and Magic Mouse send continuous scroll events and are left
/// alone; only line-based wheel events are rewritten.
@Observable
final class MouseController: FeatureModule {
    enum Status: Equatable {
        case disabled, needsPermission, ready
        /// macOS refused the event tap even though Accessibility looks granted.
        case tapFailed
    }

    let permissions: PermissionsManager
    let settings = MouseSettings()
    private(set) var status: Status = .disabled

    @ObservationIgnored private lazy var tap = EventTap { [unowned self] type, event in handle(type, event) }
    @ObservationIgnored private var scroller = SmoothScroller()
    @ObservationIgnored private var glideTimer: Timer?
    @ObservationIgnored private var lastGlideStep: TimeInterval = 0
    /// Buttons whose press was taken over, so the matching release and drags
    /// are handled the same way even if settings change mid-press.
    @ObservationIgnored private var heldButtons: [Int64: MouseButtonAction] = [:]
    @ObservationIgnored private var systemNatural = true
    @ObservationIgnored private var systemNaturalReadAt: TimeInterval = 0
    @ObservationIgnored private var isStarted = false
    /// A change is being waited for. Survives `stop`, so starting again
    /// doesn't add a second wait beside it.
    @ObservationIgnored private var isObserving = false

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reconcile()
        observeChanges()
    }

    func stop() {
        isStarted = false
        stopGlide()
        tap.remove()
        heldButtons = [:]
    }

    private func observeChanges() {
        guard !isObserving else { return }
        isObserving = true
        withObservationTracking {
            _ = permissions.accessibilityGranted
            _ = settings.isEnabled
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

    private func reconcile() {
        guard settings.isEnabled else {
            stopGlide()
            tap.remove()
            status = .disabled
            return
        }
        guard permissions.accessibilityGranted else {
            tap.remove()
            status = .needsPermission
            return
        }
        let installed = tap.install(events: [.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged],
                                    listenOnly: false)
        status = installed ? .ready : .tapFailed
    }

    // MARK: - Events

    private func handle(_ type: CGEventType, _ event: CGEvent) -> EventTap.Result {
        switch type {
        case .scrollWheel: handleScroll(event)
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: handleButton(type, event)
        default: .pass
        }
    }

    private func handleScroll(_ event: CGEvent) -> EventTap.Result {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return .pass }
        let invert = settings.scrollDirection.invertsWheel(isContinuous: false, systemNatural: currentSystemNatural())
        let sign: Double = invert ? -1 : 1

        guard settings.smoothScrolling else {
            if invert { Self.negateScroll(event) }
            return .pass
        }
        // Prefer whole lines; fall back to the sign of the point delta for
        // the fractional ticks some wheels send.
        let linesY = Self.lines(event, line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1)
        let linesX = Self.lines(event, line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2)
        guard linesX != 0 || linesY != 0 else { return .pass }
        scroller.speed = settings.scrollSpeed
        scroller.smoothness = settings.glide
        scroller.add(linesX: linesX * sign, linesY: linesY * sign, at: ProcessInfo.processInfo.systemUptime)
        startGlide()
        return .drop
    }

    private static func lines(_ event: CGEvent, line: CGEventField, point: CGEventField) -> Double {
        let lines = event.getIntegerValueField(line)
        if lines != 0 { return Double(lines) }
        let points = event.getDoubleValueField(point)
        return points == 0 ? 0 : (points > 0 ? 1 : -1)
    }

    private static func negateScroll(_ event: CGEvent) {
        for field in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                      .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2] {
            event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
        }
        for field in [CGEventField.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
            event.setDoubleValueField(field, value: -event.getDoubleValueField(field))
        }
    }

    private func handleButton(_ type: CGEventType, _ event: CGEvent) -> EventTap.Result {
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        let action: MouseButtonAction
        if type == .otherMouseDown {
            guard let button = MouseButton(rawValue: Int(number)) else { return .pass }
            action = settings.action(for: button)
            guard action != .passThrough else { return .pass }
            heldButtons[number] = action
            if let keystroke = action.keystroke {
                EventTap.postKeystroke(keyCode: keystroke.keyCode, flags: keystroke.flags)
            }
        } else {
            guard let held = heldButtons[number] else { return .pass }
            action = held
            if type == .otherMouseUp { heldButtons[number] = nil }
        }
        if action == .middleClick {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
            return .pass
        }
        return .drop
    }

    /// macOS's natural-scrolling switch, re-read at most every two seconds
    /// so a change in System Settings is picked up without a relaunch.
    private func currentSystemNatural() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - systemNaturalReadAt > 2 {
            systemNaturalReadAt = now
            let key = "com.apple.swipescrolldirection" as CFString
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
            // Missing means the default, which is natural.
            systemNatural = CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? Bool ?? true
        }
        return systemNatural
    }

    // MARK: - Glide

    private func startGlide() {
        guard glideTimer == nil else { return }
        lastGlideStep = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.glideStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
    }

    private func glideStep() {
        let now = ProcessInfo.processInfo.systemUptime
        let step = scroller.step(dt: now - lastGlideStep)
        lastGlideStep = now
        if step.x != 0 || step.y != 0 {
            Self.postPixelScroll(x: step.x, y: step.y)
        }
        if scroller.isIdle { stopGlide() }
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        scroller.stop()
    }

    private static func postPixelScroll(x: Int, y: Int) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(y), wheel2: Int32(x), wheel3: 0) else { return }
        // Continuous, like a trackpad, so apps scroll by pixels rather than
        // snapping to lines.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }
}
