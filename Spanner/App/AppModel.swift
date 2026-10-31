import Observation
import SwiftUI

/// Owns every long-lived service. Views receive the individual services
/// through the environment (see `injectServices`), never the model itself,
/// so each view depends only on what it uses.
@Observable
final class AppModel {
    let permissions = PermissionsManager()
    let battery = BatteryService()
    let keepAwake = KeepAwakeController()
    let updates = UpdatesController()
    let loginItem = LoginItemController()
    let switcher: SwitcherController

    /// Section shown in the main window; menu bar shortcuts set it before
    /// opening the window.
    var selectedSection: AppSection = .battery

    init() {
        switcher = SwitcherController(permissions: permissions)
    }

    func start() {
        permissions.startMonitoring()
        battery.start()
        switcher.start()
    }

    /// Runs on quit. Must restore anything Spanner changed system-wide.
    func shutdown() {
        switcher.stop()
        keepAwake.stop()
        battery.stop()
        permissions.stopMonitoring()
    }
}

/// Sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable {
    case battery, switcher, keepAwake, permissions, general

    var id: Self { self }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .switcher: "Window Switcher"
        case .keepAwake: "Keep Awake"
        case .permissions: "Permissions"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.100percent.bolt"
        case .switcher: "rectangle.on.rectangle"
        case .keepAwake: "cup.and.heat.waves.fill"
        case .permissions: "hand.raised.fill"
        case .general: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .battery: FeatureTint.battery
        case .switcher: FeatureTint.switcher
        case .keepAwake: FeatureTint.keepAwake
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
            .environment(model.keepAwake)
            .environment(model.updates)
            .environment(model.loginItem)
            .environment(model.switcher)
    }
}
