import Observation
import SwiftUI

/// Owns every long-lived service. Views receive the individual services
/// through the environment (see `injectServices`), never the model itself,
/// so each view depends only on what it uses.
@Observable
final class AppModel {
    let permissions = PermissionsManager()
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
    var selectedSection: AppSection = .battery

    init() {
        headphones = HeadphoneMonitor(permissions: permissions)
        switcher = SwitcherController(permissions: permissions, hotkeys: hotkeys)
        snapping = SnapController(permissions: permissions, hotkeys: hotkeys)
        mouse = MouseController(permissions: permissions)
        sound = SoundController(permissions: permissions, hotkeys: hotkeys)
        displays = DisplayController(permissions: permissions)
    }

    func start() {
        permissions.startMonitoring()
        battery.start()
        headphones.start()
        energy.start()
        switcher.start()
        snapping.start()
        mouse.start()
        sound.start()
        displays.start()
    }

    /// Runs on quit. Must restore anything Spanner changed system-wide.
    func shutdown() {
        displays.stop()
        sound.stop()
        mouse.stop()
        snapping.stop()
        switcher.stop()
        keepAwake.stop()
        system.stop()
        energy.stop()
        headphones.stop()
        battery.stop()
        permissions.stopMonitoring()
    }
}

/// Sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable {
    case battery, system, switcher, snapping, mouse, sound, displays, keepAwake, menuBar, permissions, general

    var id: Self { self }

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
