import SwiftUI

/// Tiles of the menu bar panel that can be hidden, in panel order. Every
/// tile is shown until it's turned off.
enum PanelTile: String, CaseIterable, Identifiable {
    case battery, system, headphones, keepAwake, switcher, displays

    var id: Self { self }

    /// `@AppStorage` key for showing the tile. Derived from the raw value,
    /// so renaming a case resets that tile to shown.
    var storageKey: String { "menuBar.shows.\(rawValue)" }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .system: "System"
        case .headphones: "Headphones"
        case .keepAwake: "Keep Awake"
        case .switcher: "Window Switcher"
        case .displays: "Display Brightness"
        }
    }

    var symbol: String {
        switch self {
        case .battery: AppSection.battery.symbol
        case .system: AppSection.system.symbol
        case .headphones: "airpods.pro"
        case .keepAwake: AppSection.keepAwake.symbol
        case .switcher: AppSection.switcher.symbol
        case .displays: AppSection.displays.symbol
        }
    }

    var tint: Color {
        switch self {
        case .battery: FeatureTint.battery
        case .system: FeatureTint.system
        case .headphones: FeatureTint.switcher
        case .keepAwake: FeatureTint.keepAwake
        case .switcher: FeatureTint.switcher
        case .displays: FeatureTint.displays
        }
    }
}

/// Main-window page choosing which tiles the menu bar panel shows.
struct MenuBarSettingsPage: View {
    var body: some View {
        Page {
            PageHeader(title: "Menu Bar",
                       subtitle: "Choose what the panel shows when you click the wrench in the menu bar.",
                       symbol: AppSection.menuBar.symbol, tint: FeatureTint.menuBar)

            SettingsGroup(title: "Show in the panel",
                          footer: "A reminder also appears whenever Spanner is missing a permission it needs.") {
                ForEach(PanelTile.allCases) { PanelTileRow(tile: $0) }
            }
        }
    }
}

private struct PanelTileRow: View {
    let tile: PanelTile
    @AppStorage private var isShown: Bool
    @Environment(BatteryService.self) private var battery
    @Environment(PermissionsManager.self) private var permissions

    init(tile: PanelTile) {
        self.tile = tile
        _isShown = AppStorage(wrappedValue: true, tile.storageKey)
    }

    var body: some View {
        SettingsRow(title: tile.title, subtitle: subtitle, symbol: tile.symbol, tint: tile.tint) {
            Toggle("Show \(tile.title) in the panel", isOn: $isShown)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(isUnavailable)
        }
    }

    /// The tile can never appear on this Mac, whatever the setting.
    private var isUnavailable: Bool {
        tile == .battery && battery.hasBattery == false
    }

    private var subtitle: String {
        switch tile {
        case .battery:
            isUnavailable ? "This Mac has no battery." : "Charge, status and power draw."
        case .system:
            "CPU, GPU and memory gauges. Load is measured only while they're on screen."
        case .headphones:
            permissions.isGranted(.bluetooth)
                ? "Battery of connected AirPods and headphones, while they're connected."
                : "Needs Bluetooth permission, which you can grant in Permissions."
        case .keepAwake:
            "Turn Keep Awake on or off and pick a duration."
        case .switcher:
            "Turn the window switcher on or off."
        case .displays:
            "Brightness sliders, when a connected monitor supports brightness control."
        }
    }
}
