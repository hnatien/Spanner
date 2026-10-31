import Foundation
import Observation
import SpannerCore

/// Switcher preferences, persisted in UserDefaults. The controller observes
/// these and re-registers shortcuts when they change.
@Observable
final class SwitcherSettings {
    var isEnabled: Bool { didSet { store(isEnabled, Key.enabled) } }
    var trigger: SwitcherTrigger { didSet { store(trigger.rawValue, Key.trigger) } }
    var appWindowsEnabled: Bool { didSet { store(appWindowsEnabled, Key.appWindows) } }
    var includeMinimized: Bool { didSet { store(includeMinimized, Key.minimized) } }
    var includeOtherSpaces: Bool { didSet { store(includeOtherSpaces, Key.otherSpaces) } }
    var thumbnailSize: ThumbnailSize { didSet { store(thumbnailSize.rawValue, Key.size) } }
    var overlayScreen: OverlayScreen { didSet { store(overlayScreen.rawValue, Key.screen) } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let enabled = "switcher.enabled"
        static let trigger = "switcher.trigger"
        static let appWindows = "switcher.appWindowsEnabled"
        static let minimized = "switcher.includeMinimized"
        static let otherSpaces = "switcher.includeOtherSpaces"
        static let size = "switcher.thumbnailSize"
        static let screen = "switcher.overlayScreen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        trigger = defaults.string(forKey: Key.trigger).flatMap(SwitcherTrigger.init) ?? .option
        appWindowsEnabled = defaults.object(forKey: Key.appWindows) as? Bool ?? true
        includeMinimized = defaults.object(forKey: Key.minimized) as? Bool ?? true
        includeOtherSpaces = defaults.object(forKey: Key.otherSpaces) as? Bool ?? true
        thumbnailSize = defaults.string(forKey: Key.size).flatMap(ThumbnailSize.init) ?? .medium
        overlayScreen = defaults.string(forKey: Key.screen).flatMap(OverlayScreen.init) ?? .pointer
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
