import Foundation
import Observation
import SpannerCore

/// Sound preferences, persisted in UserDefaults.
@Observable
final class SoundSettings {
    /// Per-app volume by bundle ID (or executable name for apps without one).
    private(set) var volumes: [String: AppVolume] { didSet { storeVolumes() } }
    var micMuteShortcut: KeyShortcut? { didSet { storeShortcut() } }
    var showsMicMuteHUD: Bool { didSet { defaults.set(showsMicMuteHUD, forKey: Key.hud) } }
    /// Input volume saved when muting a microphone that has no mute switch,
    /// kept on disk so a crash while muted doesn't lose it.
    var savedInputVolume: Float? {
        didSet { defaults.set(savedInputVolume, forKey: Key.savedInputVolume) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let volumes = "sound.appVolumes"
        static let shortcut = "sound.micMuteShortcut"
        static let hud = "sound.showsMicMuteHUD"
        static let savedInputVolume = "sound.savedInputVolume"
    }

    /// ⌃⌥M; nothing in macOS or the snapping defaults uses it.
    static let defaultMicMuteShortcut = KeyShortcut(keyCode: 0x2E,
                                                    modifiers: KeyShortcut.Modifier.control | KeyShortcut.Modifier.option)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volumes = defaults.data(forKey: Key.volumes)
            .flatMap { try? JSONDecoder().decode([String: AppVolume].self, from: $0) } ?? [:]
        if let data = defaults.data(forKey: Key.shortcut) {
            micMuteShortcut = try? JSONDecoder().decode(KeyShortcut?.self, from: data)
        } else {
            micMuteShortcut = Self.defaultMicMuteShortcut
        }
        showsMicMuteHUD = defaults.object(forKey: Key.hud) as? Bool ?? true
        savedInputVolume = defaults.object(forKey: Key.savedInputVolume) as? Float
    }

    func volume(for key: String) -> AppVolume {
        volumes[key] ?? AppVolume()
    }

    func setVolume(_ volume: AppVolume, for key: String) {
        // Unity settings are dropped so the store only holds real changes.
        volumes[key] = volume.isUnity ? nil : volume
    }

    func resetVolumes() {
        volumes = [:]
    }

    private func storeVolumes() {
        defaults.set(try? JSONEncoder().encode(volumes), forKey: Key.volumes)
    }

    private func storeShortcut() {
        defaults.set(try? JSONEncoder().encode(micMuteShortcut), forKey: Key.shortcut)
    }
}
