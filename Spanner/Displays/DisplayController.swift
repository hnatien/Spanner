import AppKit
import CoreAudio
import Observation
import SpannerCore

/// One external monitor and what Spanner knows about its DDC controls.
struct ExternalDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    /// Whether an AV service that can carry DDC was found for it.
    let hasDDC: Bool
    /// 0...1, nil until read (or if the monitor doesn't report it).
    var brightness: Double?
    var volume: Double?
    var isMuted = false
    /// Raw maxima reported by the monitor; MCCS's usual 100 until read.
    var maxBrightness: UInt16 = 100
    var maxVolume: UInt16 = 100
    var isReading = false
}

/// Brightness and volume for external monitors over DDC/CI, with the
/// keyboard's brightness and volume keys routed to them and an on-screen
/// display. Built-in and Apple displays are left to macOS.
///
/// DDC needs no permission. Taking over the media keys needs an active event
/// tap, so it needs Accessibility.
@Observable
final class DisplayController {
    enum BrightnessKeyTarget: String, CaseIterable, Identifiable {
        case pointer, allExternal

        var id: Self { self }

        var title: String {
            switch self {
            case .pointer: "Display with the pointer"
            case .allExternal: "All displays"
            }
        }
    }

    let permissions: PermissionsManager
    private(set) var displays: [ExternalDisplay] = []

    var mediaKeysEnabled: Bool {
        didSet { UserDefaults.standard.set(mediaKeysEnabled, forKey: Key.mediaKeys) }
    }
    var brightnessKeyTarget: BrightnessKeyTarget {
        didSet { UserDefaults.standard.set(brightnessKeyTarget.rawValue, forKey: Key.target) }
    }

    @ObservationIgnored private var channels: [CGDirectDisplayID: DDCChannel] = [:]
    @ObservationIgnored private lazy var keyTap = EventTap { [unowned self] type, event in handleKey(type, event) }
    @ObservationIgnored private let hud = HUDPanel()
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var isStarted = false

    private enum Key {
        static let mediaKeys = "displays.mediaKeysEnabled"
        static let target = "displays.brightnessKeyTarget"
    }

    /// One key press moves 1/16 of the range, like macOS; ⌥⇧ moves a quarter of that.
    private static let step = 1.0 / 16
    private static let fineStep = 1.0 / 64

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        mediaKeysEnabled = UserDefaults.standard.object(forKey: Key.mediaKeys) as? Bool ?? true
        brightnessKeyTarget = UserDefaults.standard.string(forKey: Key.target).flatMap(BrightnessKeyTarget.init) ?? .pointer
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
        reconcileKeyTap()
        observeChanges()
    }

    func stop() {
        isStarted = false
        keyTap.remove()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func observeChanges() {
        withObservationTracking {
            _ = permissions.accessibilityGranted
            _ = mediaKeysEnabled
            _ = displays.count
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.reconcileKeyTap()
                self.observeChanges()
            }
        }
    }

    /// The tap only exists while there is an external display to control.
    private func reconcileKeyTap() {
        let wanted = mediaKeysEnabled && permissions.accessibilityGranted && displays.contains(where: \.hasDDC)
        if wanted {
            keyTap.install(events: [CGEventType(rawValue: Self.systemDefinedEventType)!, .keyDown, .keyUp], listenOnly: false)
        } else {
            keyTap.remove()
        }
    }

    // MARK: - Discovery

    func refreshDisplays() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
        let external = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        let candidates = external.map { id in
            DisplayServiceMatcher.Display(id: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                          serial: CGDisplaySerialNumber(id), name: Self.name(of: id))
        }
        let services = DDCServiceFinder.externalServices()
        let matches = DisplayServiceMatcher.match(displays: candidates, services: services.map(\.attributes))

        let previous = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        channels = [:]
        displays = candidates.map { candidate in
            let channel = matches[candidate.id].map { services[$0].channel }
            channels[candidate.id] = channel
            var display = previous[candidate.id]
                ?? ExternalDisplay(id: candidate.id, name: candidate.name, hasDDC: channel != nil)
            if display.hasDDC != (channel != nil) {
                display = ExternalDisplay(id: candidate.id, name: candidate.name, hasDDC: channel != nil)
            }
            return display
        }
        for display in displays where display.hasDDC && display.brightness == nil && !display.isReading {
            readLevels(of: display.id)
        }
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { $0.displayID == id }?.localizedName ?? "Display \(id)"
    }

    private func readLevels(of id: CGDirectDisplayID) {
        guard let channel = channels[id] else { return }
        update(id) { $0.isReading = true }
        Task { [weak self] in
            let brightness = await channel.read(.brightness)
            let volume = await channel.read(.volume)
            guard let self else { return }
            self.update(id) { display in
                display.isReading = false
                if let brightness {
                    display.brightness = brightness.fraction
                    display.maxBrightness = max(brightness.maximum, 1)
                }
                if let volume {
                    display.volume = volume.fraction
                    display.maxVolume = max(volume.maximum, 1)
                }
            }
        }
    }

    private func update(_ id: CGDirectDisplayID, _ change: (inout ExternalDisplay) -> Void) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        change(&displays[index])
    }

    // MARK: - Control

    func setBrightness(_ fraction: Double, for id: CGDirectDisplayID) {
        guard let channel = channels[id], let display = displays.first(where: { $0.id == id }) else { return }
        let clamped = min(max(fraction, 0), 1)
        update(id) { $0.brightness = clamped }
        channel.write(.brightness, value: DDC.value(for: clamped, maximum: display.maxBrightness))
    }

    func setVolume(_ fraction: Double, for id: CGDirectDisplayID) {
        guard let channel = channels[id], let display = displays.first(where: { $0.id == id }) else { return }
        let clamped = min(max(fraction, 0), 1)
        update(id) { $0.volume = clamped; $0.isMuted = false }
        channel.write(.volume, value: DDC.value(for: clamped, maximum: display.maxVolume))
    }

    /// MCCS mute: 1 = muted, 2 = unmuted. Not every monitor implements it,
    /// so muting also sends volume 0 and unmuting restores the level.
    func toggleMute(for id: CGDirectDisplayID) {
        guard let channel = channels[id], let display = displays.first(where: { $0.id == id }) else { return }
        let mute = !display.isMuted
        update(id) { $0.isMuted = mute }
        channel.write(.mute, value: mute ? 1 : 2)
        channel.write(.volume, value: mute ? 0 : DDC.value(for: display.volume ?? 0.5, maximum: display.maxVolume))
    }

    // MARK: - Media keys

    /// `NX_SYSDEFINED`: media and brightness keys arrive as this event type.
    private static let systemDefinedEventType: UInt32 = 14
    private enum MediaKey: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> EventTap.Result {
        let key: MediaKey
        let isDown: Bool
        if type.rawValue == Self.systemDefinedEventType {
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return .pass }
            let data = nsEvent.data1
            guard let mediaKey = MediaKey(rawValue: (data & 0xFFFF_0000) >> 16) else { return .pass }
            key = mediaKey
            isDown = ((data & 0xFF00) >> 8) == 0x0A
        } else {
            // Some Apple keyboards send brightness as plain key codes.
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 144: key = .brightnessUp
            case 145: key = .brightnessDown
            default: return .pass
            }
            isDown = type == .keyDown
        }

        let flags = event.flags
        let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .brightnessUp, .brightnessDown:
            return handleBrightness(up: key == .brightnessUp, step: step, isDown: isDown)
        case .soundUp, .soundDown, .mute:
            return handleVolume(key, step: step, isDown: isDown)
        }
    }

    private func handleBrightness(up: Bool, step: Double, isDown: Bool) -> EventTap.Result {
        let targets: [ExternalDisplay]
        var passToSystem = false
        switch brightnessKeyTarget {
        case .pointer:
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
                  let display = displays.first(where: { $0.id == screen.displayID && $0.hasDDC }) else { return .pass }
            targets = [display]
        case .allExternal:
            targets = displays.filter(\.hasDDC)
            // The built-in display still gets the key from macOS.
            passToSystem = true
        }
        guard !targets.isEmpty else { return .pass }
        if isDown {
            for display in targets {
                setBrightness((display.brightness ?? 0.5) + (up ? step : -step), for: display.id)
            }
            if let shown = displays.first(where: { $0.id == targets[0].id }) {
                hud.show(symbol: "sun.max.fill", title: targets.count == 1 ? shown.name : "External displays",
                         level: shown.brightness, on: NSScreen.screens.first { $0.displayID == shown.id })
            }
        }
        return passToSystem ? .pass : .drop
    }

    /// Volume keys go to a monitor only when macOS is playing through its
    /// speakers (HDMI/DisplayPort audio), whose volume macOS can't set.
    private func handleVolume(_ key: MediaKey, step: Double, isDown: Bool) -> EventTap.Result {
        guard let display = displayForCurrentAudioOutput() else { return .pass }
        if isDown {
            switch key {
            case .mute: toggleMute(for: display.id)
            case .soundUp: setVolume((display.volume ?? 0.5) + step, for: display.id)
            default: setVolume((display.volume ?? 0.5) - step, for: display.id)
            }
            if let shown = displays.first(where: { $0.id == display.id }) {
                hud.show(symbol: shown.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: shown.name,
                         level: shown.isMuted ? 0 : shown.volume, on: NSScreen.screens.first { $0.displayID == shown.id })
            }
        }
        return .drop
    }

    private func displayForCurrentAudioOutput() -> ExternalDisplay? {
        guard let id = AudioHardware.defaultDevice(input: false), let device = AudioHardware.device(id),
              device.isDisplayAudio else { return nil }
        // If macOS can set the device's volume itself (on the main element
        // or per channel), let it.
        let scope = kAudioObjectPropertyScopeOutput
        if AudioHardware.isSettable(id, kAudioDevicePropertyVolumeScalar, scope: scope)
            || AudioHardware.isSettable(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: 1) { return nil }
        let candidates = displays.filter(\.hasDDC)
        // The display's audio device is normally named after the monitor.
        return candidates.first { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }
            ?? (candidates.count == 1 ? candidates[0] : nil)
    }
}
