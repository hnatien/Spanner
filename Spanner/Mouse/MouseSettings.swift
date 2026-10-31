import Foundation
import Observation
import SpannerCore

/// Mouse preferences, persisted in UserDefaults. Off by default: the module
/// rewrites input, so the person turns it on deliberately.
@Observable
final class MouseSettings {
    var isEnabled: Bool { didSet { store(isEnabled, Key.enabled) } }
    var scrollDirection: MouseScrollDirection { didSet { store(scrollDirection.rawValue, Key.direction) } }
    var smoothScrolling: Bool { didSet { store(smoothScrolling, Key.smooth) } }
    /// Distance per wheel tick when smooth scrolling, as a multiplier.
    var scrollSpeed: Double { didSet { store(scrollSpeed, Key.speed) } }
    /// Glide time constant in seconds.
    var glide: Double { didSet { store(glide, Key.glide) } }
    var buttonActions: [MouseButton: MouseButtonAction] {
        didSet {
            store(Dictionary(uniqueKeysWithValues: buttonActions.map { (String($0.key.rawValue), $0.value.rawValue) }),
                  Key.buttons)
        }
    }

    static let speedRange: ClosedRange<Double> = 0.5...3
    static let glideRange: ClosedRange<Double> = 0.04...0.2

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let enabled = "mouse.enabled"
        static let direction = "mouse.scrollDirection"
        static let smooth = "mouse.smoothScrolling"
        static let speed = "mouse.scrollSpeed"
        static let glide = "mouse.glide"
        static let buttons = "mouse.buttonActions"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        scrollDirection = defaults.string(forKey: Key.direction).flatMap(MouseScrollDirection.init) ?? .standard
        smoothScrolling = defaults.object(forKey: Key.smooth) as? Bool ?? true
        scrollSpeed = defaults.object(forKey: Key.speed) as? Double ?? 1
        glide = defaults.object(forKey: Key.glide) as? Double ?? 0.09
        let stored = defaults.dictionary(forKey: Key.buttons) as? [String: String] ?? [:]
        buttonActions = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { button in
            (button, stored[String(button.rawValue)].flatMap(MouseButtonAction.init) ?? button.defaultAction)
        })
    }

    func action(for button: MouseButton) -> MouseButtonAction {
        buttonActions[button] ?? button.defaultAction
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
