import Foundation
import Observation
import SpannerCore

/// Window snapping preferences, persisted in UserDefaults.
@Observable
final class SnapSettings {
    var isEnabled: Bool { didSet { store(isEnabled, Key.enabled) } }
    var dragSnapping: Bool { didSet { store(dragSnapping, Key.drag) } }
    /// Overrides of the default shortcuts. A key mapped to nil was cleared.
    private var shortcutOverrides: [SnapAction: KeyShortcut?] { didSet { storeShortcuts() } }
    private var rules: [String: DisplaySnapRule] { didSet { storeRules() } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let enabled = "snapping.enabled"
        static let drag = "snapping.dragSnapping"
        static let shortcuts = "snapping.shortcuts"
        static let rules = "snapping.displayRules"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        dragSnapping = defaults.object(forKey: Key.drag) as? Bool ?? true
        let storedShortcuts = defaults.data(forKey: Key.shortcuts)
            .flatMap { try? JSONDecoder().decode([String: KeyShortcut?].self, from: $0) } ?? [:]
        shortcutOverrides = Dictionary(uniqueKeysWithValues: storedShortcuts.compactMap { key, value in
            SnapAction(rawValue: key).map { ($0, value) }
        })
        rules = defaults.data(forKey: Key.rules)
            .flatMap { try? JSONDecoder().decode([String: DisplaySnapRule].self, from: $0) } ?? [:]
    }

    func shortcut(for action: SnapAction) -> KeyShortcut? {
        if let override = shortcutOverrides[action] { return override }
        return action.defaultShortcut
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: SnapAction) {
        shortcutOverrides[action] = .some(shortcut)
    }

    func resetShortcuts() {
        shortcutOverrides = [:]
    }

    /// Every action's current shortcut, for registering hotkeys.
    var activeShortcuts: [(SnapAction, KeyShortcut)] {
        SnapAction.allCases.compactMap { action in shortcut(for: action).map { (action, $0) } }
    }

    func rule(for displayKey: String) -> DisplaySnapRule {
        rules[displayKey] ?? DisplaySnapRule()
    }

    func setRule(_ rule: DisplaySnapRule, for displayKey: String) {
        rules[displayKey] = rule
    }

    private func storeShortcuts() {
        let encodable = Dictionary(uniqueKeysWithValues: shortcutOverrides.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(encodable), forKey: Key.shortcuts)
    }

    private func storeRules() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: Key.rules)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
