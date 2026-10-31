import AppKit
import CoreAudio
import Observation
import OSLog
import SpannerCore

/// An app in the volume mixer: all of its audio processes (browsers and
/// Electron apps play from helper processes) under one slider.
struct MixerApp: Identifiable, Equatable {
    /// Bundle ID of the app, or the process name for bare executables.
    let id: String
    let name: String
    /// Path of the app bundle, for its icon.
    let bundlePath: String?
    let processes: Set<AudioObjectID>
    let isPlaying: Bool
}

/// Output and input devices, the per-app volume mixer, and the mic mute
/// shortcut. Device switching and mic mute use public Core Audio properties
/// and need no permission; the mixer needs System Audio Recording.
@Observable
final class SoundController {
    let permissions: PermissionsManager
    let settings = SoundSettings()

    private(set) var outputDevices: [AudioDevice] = []
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    private(set) var isMicMuted = false
    /// Apps playing now, plus apps with a changed volume that are running.
    private(set) var mixerApps: [MixerApp] = []
    private(set) var micShortcutUnavailable = false
    /// Last failure to apply a volume, shown on the Sound page.
    private(set) var mixerError: String?

    /// Set by mixer views while on screen, so the app list refreshes often.
    var isMixerVisible = false {
        didSet { if isMixerVisible && !oldValue { refreshApps() } }
    }

    var defaultOutput: AudioDevice? { outputDevices.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { inputDevices.first { $0.id == defaultInputID } }

    @ObservationIgnored private let hotkeys: HotkeyCenter
    @ObservationIgnored private var micHotkey: UInt32?
    @ObservationIgnored private var taps: [String: AppVolumeTap] = [:]
    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var appInfoCache: [pid_t: (key: String, name: String, bundlePath: String?)] = [:]
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let hud = HUDPanel()
    private static let log = Logger(subsystem: "dev.spanner.Spanner", category: "Sound")

    init(permissions: PermissionsManager, hotkeys: HotkeyCenter) {
        self.permissions = permissions
        self.hotkeys = hotkeys
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshDevices()
        refreshApps()
        listen(kAudioHardwarePropertyDevices) { $0.refreshDevices() }
        listen(kAudioHardwarePropertyDefaultOutputDevice) { controller in
            controller.refreshDevices()
            // Taps are bound to the output device; rebuild them for the new one.
            controller.rebuildAllTaps()
        }
        listen(kAudioHardwarePropertyDefaultInputDevice) { $0.refreshDevices() }
        listen(kAudioHardwarePropertyProcessObjectList) { $0.refreshApps() }
        registerMicHotkey()
        observeChanges()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                // Playing state has no cheap notification; poll while it matters.
                if self.isMixerVisible || !self.taps.isEmpty { self.refreshApps() }
                self.refreshMicState()
            }
        }
    }

    func stop() {
        isStarted = false
        pollTask?.cancel()
        pollTask = nil
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, block)
        }
        listeners = []
        taps.values.forEach { $0.invalidate() }
        taps = [:]
        if let micHotkey { hotkeys.unregister([micHotkey]) }
        micHotkey = nil
    }

    private func observeChanges() {
        withObservationTracking {
            _ = settings.micMuteShortcut
            _ = permissions.systemAudioGranted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.registerMicHotkey()
                self.applyTaps()
                self.observeChanges()
            }
        }
    }

    private func listen(_ selector: AudioObjectPropertySelector, _ action: @escaping (SoundController) -> Void) {
        let address = AudioHardware.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Delivered on the main queue (see the registration below).
            MainActor.assumeIsolated {
                guard let self, self.isStarted else { return }
                action(self)
            }
        }
        var registered = address
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &registered, .main, block) == noErr {
            listeners.append((address, block))
        }
    }

    // MARK: - Devices

    func refreshDevices() {
        let devices = AudioHardware.devices()
        outputDevices = devices.filter(\.hasOutput)
        inputDevices = devices.filter(\.hasInput)
        defaultOutputID = AudioHardware.defaultDevice(input: false)
        defaultInputID = AudioHardware.defaultDevice(input: true)
        refreshMicState()
    }

    func selectOutput(_ device: AudioDevice) {
        AudioHardware.setDefaultDevice(device.id, input: false)
        refreshDevices()
    }

    func selectInput(_ device: AudioDevice) {
        AudioHardware.setDefaultDevice(device.id, input: true)
        refreshDevices()
    }

    // MARK: - Microphone

    private func registerMicHotkey() {
        if let micHotkey { hotkeys.unregister([micHotkey]) }
        micHotkey = nil
        micShortcutUnavailable = false
        guard let shortcut = settings.micMuteShortcut else { return }
        micHotkey = hotkeys.register(shortcut) { [weak self] in self?.toggleMicMute(fromShortcut: true) }
        micShortcutUnavailable = micHotkey == nil
    }

    /// Mutes the default input with its mute switch, or, for microphones
    /// without one, by setting its volume to zero and remembering the level.
    func toggleMicMute(fromShortcut: Bool = false) {
        guard let input = defaultInputID else {
            NSSound.beep()
            return
        }
        let mute = !isMicMuted
        let scope = kAudioObjectPropertyScopeInput
        if AudioHardware.isSettable(input, kAudioDevicePropertyMute, scope: scope) {
            AudioHardware.set(input, kAudioDevicePropertyMute, scope: scope, to: UInt32(mute ? 1 : 0))
        } else if AudioHardware.isSettable(input, kAudioDevicePropertyVolumeScalar, scope: scope) {
            if mute {
                settings.savedInputVolume = AudioHardware.get(input, kAudioDevicePropertyVolumeScalar, scope: scope, as: Float32.self)
                AudioHardware.set(input, kAudioDevicePropertyVolumeScalar, scope: scope, to: Float32(0))
            } else {
                AudioHardware.set(input, kAudioDevicePropertyVolumeScalar, scope: scope,
                                  to: Float32(settings.savedInputVolume ?? 0.75))
                settings.savedInputVolume = nil
            }
        } else {
            NSSound.beep()
            return
        }
        refreshMicState()
        if fromShortcut && settings.showsMicMuteHUD {
            hud.show(symbol: isMicMuted ? "mic.slash.fill" : "mic.fill",
                     title: isMicMuted ? "Microphone muted" : "Microphone on", level: nil)
        }
    }

    private func refreshMicState() {
        guard let input = defaultInputID else {
            isMicMuted = false
            return
        }
        let scope = kAudioObjectPropertyScopeInput
        let muted: Bool
        if let flag = AudioHardware.get(input, kAudioDevicePropertyMute, scope: scope, as: UInt32.self),
           AudioHardware.isSettable(input, kAudioDevicePropertyMute, scope: scope) {
            muted = flag != 0
        } else {
            muted = settings.savedInputVolume != nil
                && (AudioHardware.get(input, kAudioDevicePropertyVolumeScalar, scope: scope, as: Float32.self) ?? 1) == 0
        }
        if muted != isMicMuted { isMicMuted = muted }
    }

    // MARK: - Mixer

    func volume(for app: MixerApp) -> AppVolume {
        settings.volume(for: app.id)
    }

    func setVolume(_ volume: AppVolume, for app: MixerApp) {
        settings.setVolume(volume, for: app.id)
        if let tap = taps[app.id], !volume.isUnity {
            tap.setGain(volume.gain)
        } else {
            applyTaps()
        }
    }

    func resetVolumes() {
        settings.resetVolumes()
        applyTaps()
    }

    func refreshApps() {
        var groups: [String: (name: String, bundlePath: String?, processes: Set<AudioObjectID>, playing: Bool)] = [:]
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = AudioHardware.processes().filter { $0.pid != ownPID }
        // Forget exited processes so a reused PID isn't attributed to the old app.
        let live = Set(processes.map(\.pid))
        appInfoCache = appInfoCache.filter { live.contains($0.key) }
        for process in processes {
            let info = appInfo(for: process)
            var group = groups[info.key] ?? (info.name, info.bundlePath, [], false)
            group.processes.insert(process.object)
            group.playing = group.playing || process.isPlaying
            groups[info.key] = group
        }
        let apps = groups
            .filter { key, group in group.playing || !settings.volume(for: key).isUnity }
            .map { key, group in
                MixerApp(id: key, name: group.name, bundlePath: group.bundlePath, processes: group.processes,
                         isPlaying: group.playing)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if apps != mixerApps { mixerApps = apps }
        // Keep processes for every app with a setting, playing or not, so a
        // quiet app is already turned down when it starts playing.
        applyTaps(groups: groups.mapValues(\.processes))
    }

    /// Resolves which app a process belongs to: its outermost app bundle,
    /// so helpers count toward their browser or Electron app.
    private func appInfo(for process: AudioHardware.AudioProcess) -> (key: String, name: String, bundlePath: String?) {
        if let cached = appInfoCache[process.pid] { return cached }
        var info: (key: String, name: String, bundlePath: String?)
        if let path = ProcessPath.executable(of: process.pid), let appPath = AppBundlePath.outermostApp(in: path) {
            let bundle = Bundle(path: appPath)
            let name = FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
            info = (bundle?.bundleIdentifier ?? process.bundleID ?? appPath, name, appPath)
        } else {
            let running = NSRunningApplication(processIdentifier: process.pid)
            let name = running?.localizedName ?? ProcessPath.executable(of: process.pid).map { ($0 as NSString).lastPathComponent }
                ?? process.bundleID ?? "PID \(process.pid)"
            info = (process.bundleID ?? name, name, running?.bundleURL?.path)
        }
        appInfoCache[process.pid] = info
        return info
    }

    private func rebuildAllTaps() {
        taps.values.forEach { $0.invalidate() }
        taps = [:]
        applyTaps()
    }

    private func applyTaps(groups: [String: Set<AudioObjectID>]? = nil) {
        let groups = groups ?? Dictionary(uniqueKeysWithValues: mixerApps.map { ($0.id, $0.processes) })
        // Never tap without the permission: the app would be muted while the
        // tap delivers silence.
        guard permissions.systemAudioGranted, let output = defaultOutput else {
            taps.values.forEach { $0.invalidate() }
            taps = [:]
            return
        }
        var wanted: [String: (Set<AudioObjectID>, AppVolume)] = [:]
        for (key, processes) in groups where !processes.isEmpty {
            let volume = settings.volume(for: key)
            if !volume.isUnity { wanted[key] = (processes, volume) }
        }
        for (key, tap) in taps where wanted[key] == nil {
            tap.invalidate()
            taps[key] = nil
        }
        for (key, (processes, volume)) in wanted {
            if let tap = taps[key], tap.processes == processes, tap.outputUID == output.uid {
                tap.setGain(volume.gain)
                continue
            }
            taps[key]?.invalidate()
            taps[key] = nil
            do {
                taps[key] = try AppVolumeTap(processes: processes, outputUID: output.uid, gain: volume.gain)
                mixerError = nil
            } catch {
                Self.log.error("Volume tap for \(key, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                mixerError = "Couldn't change the volume of \(mixerApps.first { $0.id == key }?.name ?? key)."
            }
        }
    }
}
