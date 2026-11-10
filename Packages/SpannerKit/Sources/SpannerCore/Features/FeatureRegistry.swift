import Foundation
import Observation

/// The parts of Spanner that can be turned off, in sidebar order.
public enum Feature: String, CaseIterable, Identifiable, Sendable {
    case battery, system, switcher, snapping, mouse, sound, displays, keepAwake

    public var id: Self { self }

    /// UserDefaults key for whether the feature is on. Derived from the raw
    /// value, so renaming a case turns that feature back on.
    public var storageKey: String { "features.\(rawValue).enabled" }
}

/// A long-lived service behind a feature. `stop` must undo everything the
/// service changed system-wide, and `start` must work again afterwards.
@MainActor
public protocol FeatureModule: AnyObject {
    func start()
    func stop()
}

public extension FeatureModule {
    /// Services that only work on demand have nothing to start.
    func start() {}
}

/// Which features are on, and the services behind each one. A feature that
/// is off has its services stopped; every feature is on until turned off.
@MainActor
@Observable
public final class FeatureRegistry {
    public private(set) var enabled: Set<Feature>

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var modules: [Feature: [any FeatureModule]] = [:]
    @ObservationIgnored private var running: Set<Feature> = []
    @ObservationIgnored private var isStarted = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(Feature.allCases.filter { defaults.object(forKey: $0.storageKey) as? Bool ?? true })
    }

    /// Enabled features, in sidebar order.
    public var enabledFeatures: [Feature] { Feature.allCases.filter(enabled.contains) }

    public func isEnabled(_ feature: Feature) -> Bool { enabled.contains(feature) }

    /// Adds services to a feature. They start in the order registered and
    /// stop in reverse.
    public func register(_ feature: Feature, _ services: [any FeatureModule]) {
        modules[feature, default: []] += services
        if running.contains(feature) { services.forEach { $0.start() } }
    }

    /// Remembers the choice and, once the registry has started, starts or
    /// stops the feature's services to match.
    public func setEnabled(_ isEnabled: Bool, for feature: Feature) {
        guard isEnabled != enabled.contains(feature) else { return }
        defaults.set(isEnabled, forKey: feature.storageKey)
        if isEnabled {
            enabled.insert(feature)
            if isStarted { start(feature) }
        } else {
            enabled.remove(feature)
            stop(feature)
        }
    }

    /// Starts the services of every enabled feature.
    public func start() {
        isStarted = true
        enabledFeatures.forEach(start)
    }

    /// Stops everything that is running. Enabled features stay enabled.
    public func stop() {
        isStarted = false
        Feature.allCases.reversed().forEach(stop)
    }

    private func start(_ feature: Feature) {
        guard running.insert(feature).inserted else { return }
        modules[feature]?.forEach { $0.start() }
    }

    private func stop(_ feature: Feature) {
        guard running.remove(feature) != nil else { return }
        modules[feature]?.reversed().forEach { $0.stop() }
    }
}
