import Foundation
import Testing
@testable import SpannerCore

@MainActor
@Suite("Feature registry")
struct FeatureRegistryTests {
    private final class Service: FeatureModule {
        let name: String
        let log: Log
        private(set) var isRunning = false

        init(_ name: String = "", log: Log = Log()) {
            self.name = name
            self.log = log
        }

        func start() {
            isRunning = true
            log.events.append("start \(name)")
        }

        func stop() {
            isRunning = false
            log.events.append("stop \(name)")
        }
    }

    private final class Log {
        var events: [String] = []
    }

    private final class OnDemandService: FeatureModule {
        private(set) var stops = 0
        func stop() { stops += 1 }
    }

    /// A private defaults domain, emptied when the test ends.
    private final class Store {
        let name = "FeatureRegistryTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: name)!
        }

        deinit {
            defaults.removePersistentDomain(forName: name)
        }
    }

    private let store = Store()

    @Test func everyFeatureIsOnUntilTurnedOff() {
        let registry = FeatureRegistry(defaults: store.defaults)
        #expect(registry.enabledFeatures == Feature.allCases)
    }

    @Test func startRunsOnlyEnabledFeatures() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let mouse = Service(), sound = Service()
        registry.register(.mouse, [mouse])
        registry.register(.sound, [sound])
        registry.setEnabled(false, for: .mouse)

        registry.start()

        #expect(!mouse.isRunning)
        #expect(sound.isRunning)
    }

    @Test func togglingBeforeStartRunsNothing() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let log = Log()
        registry.register(.mouse, [Service("mouse", log: log)])

        registry.setEnabled(false, for: .mouse)
        registry.setEnabled(true, for: .mouse)

        #expect(log.events.isEmpty)
    }

    @Test func togglingWhileRunningStopsAndRestartsTheFeature() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let log = Log()
        registry.register(.switcher, [Service("switcher", log: log)])
        registry.start()

        registry.setEnabled(false, for: .switcher)
        #expect(!registry.isEnabled(.switcher))
        registry.setEnabled(true, for: .switcher)

        #expect(log.events == ["start switcher", "stop switcher", "start switcher"])
    }

    @Test func repeatingTheSameChoiceDoesNothing() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let log = Log()
        registry.register(.sound, [Service("sound", log: log)])
        registry.start()

        registry.setEnabled(true, for: .sound)
        registry.start()

        #expect(log.events == ["start sound"])
    }

    @Test func servicesStopInReverseOrder() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let log = Log()
        registry.register(.battery, [Service("battery", log: log), Service("headphones", log: log)])
        registry.register(.displays, [Service("displays", log: log)])
        registry.start()
        log.events = []

        registry.stop()

        #expect(log.events == ["stop displays", "stop headphones", "stop battery"])
    }

    @Test func stopLeavesDisabledFeaturesAloneAndKeepsChoices() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let log = Log()
        registry.register(.mouse, [Service("mouse", log: log)])
        registry.register(.sound, [Service("sound", log: log)])
        registry.setEnabled(false, for: .mouse)
        registry.start()

        registry.stop()

        #expect(log.events == ["start sound", "stop sound"])
        #expect(registry.isEnabled(.sound))
    }

    @Test func enablingAfterStopWaitsForTheNextStart() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let mouse = Service()
        registry.register(.mouse, [mouse])
        registry.setEnabled(false, for: .mouse)
        registry.start()
        registry.stop()

        registry.setEnabled(true, for: .mouse)
        #expect(!mouse.isRunning)
        registry.start()
        #expect(mouse.isRunning)
    }

    @Test func choicesSurviveARelaunch() {
        FeatureRegistry(defaults: store.defaults).setEnabled(false, for: .keepAwake)

        let relaunched = FeatureRegistry(defaults: store.defaults)

        #expect(!relaunched.isEnabled(.keepAwake))
        #expect(relaunched.enabledFeatures == Feature.allCases.filter { $0 != .keepAwake })
    }

    @Test func onDemandServiceIsStoppedWhenItsFeatureTurnsOff() {
        let registry = FeatureRegistry(defaults: store.defaults)
        let service = OnDemandService()
        registry.register(.keepAwake, [service])
        registry.start()

        registry.setEnabled(false, for: .keepAwake)

        #expect(service.stops == 1)
    }

    @Test func serviceRegisteredWhileRunningStartsAtOnce() {
        let registry = FeatureRegistry(defaults: store.defaults)
        registry.start()
        let service = Service()

        registry.register(.system, [service])

        #expect(service.isRunning)
    }
}
