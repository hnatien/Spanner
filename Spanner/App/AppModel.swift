import Observation
import SpannerCore
import SwiftUI

/// Owns every long-lived service. Views receive the individual services
/// through the environment (see `injectServices`), never the model itself,
/// so each view depends only on what it uses.
@Observable
final class AppModel {
    let permissions = PermissionsManager()
    /// Which features are on. Starts and stops the services behind each.
    let features = FeatureRegistry()
    let battery = BatteryService()
    let headphones: HeadphoneMonitor
    let energy = EnergyMonitor()
    let system = SystemMonitor()
    let keepAwake = KeepAwakeController()
    let updates = UpdatesController()
    let loginItem = LoginItemController()
    /// Shared by every module that registers global shortcuts.
    let hotkeys = HotkeyCenter()
    let switcher: SwitcherController
    let snapping: SnapController
    let mouse: MouseController
    let sound: SoundController
    let displays: DisplayController

    /// Section shown in the main window; menu bar shortcuts set it before
    /// opening the window.
    var selectedSection: AppSection

    /// Where the main window opens: the first feature that is on.
    var homeSection: AppSection {
        features.enabledFeatures.first.map(AppSection.init) ?? .features
    }

    init() {
        headphones = HeadphoneMonitor(permissions: permissions)
        switcher = SwitcherController(permissions: permissions, hotkeys: hotkeys)
        snapping = SnapController(permissions: permissions, hotkeys: hotkeys)
        mouse = MouseController(permissions: permissions)
        sound = SoundController(permissions: permissions, hotkeys: hotkeys)
        displays = DisplayController(permissions: permissions)
        // Placeholder: `homeSection` can't be read until every property is set.
        selectedSection = .features

        features.register(.battery, [battery, headphones, energy])
        features.register(.system, [system])
        features.register(.switcher, [switcher])
        features.register(.snapping, [snapping])
        features.register(.mouse, [mouse])
        features.register(.sound, [sound])
        features.register(.displays, [displays])
        features.register(.keepAwake, [keepAwake])
        selectedSection = homeSection
    }

    func start() {
        permissions.startMonitoring()
        features.start()
    }

    /// Runs on quit. Must restore anything Spanner changed system-wide.
    func shutdown() {
        features.stop()
        permissions.stopMonitoring()
    }
}

/// Sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable {
    case battery, system, switcher, snapping, mouse, sound, displays, keepAwake, features, menuBar, permissions, general

    var id: Self { self }

    /// The page of a feature.
    init(_ feature: Feature) {
        self = switch feature {
        case .battery: .battery
        case .system: .system
        case .switcher: .switcher
        case .snapping: .snapping
        case .mouse: .mouse
        case .sound: .sound
        case .displays: .displays
        case .keepAwake: .keepAwake
        }
    }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .system: "System"
        case .switcher: "Window Switcher"
        case .snapping: "Window Snapping"
        case .mouse: "Mouse"
        case .sound: "Sound"
        case .displays: "Displays"
        case .keepAwake: "Keep Awake"
        case .features: "Manage Features"
        case .menuBar: "Menu Bar"
        case .permissions: "Permissions"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.100percent"
        case .system: "cpu"
        case .switcher: "rectangle.on.rectangle"
        case .snapping: "rectangle.split.2x2.fill"
        case .mouse: "computermouse.fill"
        case .sound: "speaker.wave.2.fill"
        case .displays: "sun.max.fill"
        case .keepAwake: "cup.and.heat.waves.fill"
        case .features: "puzzlepiece.extension.fill"
        case .menuBar: "menubar.rectangle"
        case .permissions: "hand.raised.fill"
        case .general: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .battery: FeatureTint.battery
        case .system: FeatureTint.system
        case .switcher: FeatureTint.switcher
        case .snapping: FeatureTint.snapping
        case .mouse: FeatureTint.mouse
        case .sound: FeatureTint.sound
        case .displays: FeatureTint.displays
        case .keepAwake: FeatureTint.keepAwake
        case .features: FeatureTint.features
        case .menuBar: FeatureTint.menuBar
        case .permissions: FeatureTint.permissions
        case .general: FeatureTint.general
        }
    }
}

/// Scene identifiers for `openWindow(id:)`.
enum WindowID {
    static let main = "main"
    static let onboarding = "onboarding"
}

extension View {
    func injectServices(_ model: AppModel) -> some View {
        self
            .environment(model)
            .environment(model.permissions)
            .environment(model.features)
            .environment(model.battery)
            .environment(model.headphones)
            .environment(model.energy)
            .environment(model.system)
            .environment(model.keepAwake)
            .environment(model.updates)
            .environment(model.loginItem)
            .environment(model.switcher)
            .environment(model.snapping)
            .environment(model.mouse)
            .environment(model.sound)
            .environment(model.displays)
    }
}
