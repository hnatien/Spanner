import SpannerCore
import SwiftUI

/// Main-window page for the window switcher.
struct SwitcherSettingsPage: View {
    @Environment(SwitcherController.self) private var switcher
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        @Bindable var settings = switcher.settings
        Page {
            PageHeader(title: "Window Switcher",
                       subtitle: "Hold a modifier and tap Tab to see every window, on every screen and Space, with live previews.",
                       symbol: AppSection.switcher.symbol, tint: FeatureTint.switcher) {
                Toggle("Enable window switcher", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }

            if settings.isEnabled, !switcher.rivals.runningNames.isEmpty {
                RivalSwitchersGroup(rivals: switcher.rivals, keycaps: switcher.triggerKeycaps)
            }

            if settings.isEnabled && !permissions.allGranted {
                SettingsGroup(title: "Permissions needed",
                              footer: "Accessibility is required. Without Screen Recording the switcher still works, showing app icons instead of previews.") {
                    ForEach(Permission.core.filter { !permissions.isGranted($0) }) { PermissionRow(permission: $0) }
                }
            }

            ShortcutGroup(settings: settings, shortcutUnavailable: switcher.shortcutUnavailable)

            SettingsGroup(title: "Windows") {
                SettingsRow(title: "Include minimized windows", symbol: "dock.arrow.down.rectangle", tint: .orange) {
                    Toggle("Include minimized windows", isOn: $settings.includeMinimized)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Include windows on other Spaces",
                            subtitle: "Also lists windows of hidden apps.",
                            symbol: "square.stack.3d.up.fill", tint: .teal) {
                    Toggle("Include windows on other Spaces", isOn: $settings.includeOtherSpaces)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingsRow(title: "Preview size", symbol: "rectangle.grid.2x2.fill", tint: .purple) {
                    Picker("Preview size", selection: $settings.thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Show switcher on", symbol: "display.2", tint: .blue) {
                    Picker("Show switcher on", selection: $settings.overlayScreen) {
                        ForEach(OverlayScreen.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

/// Warns that another switcher is running. Carbon gives a shortcut to
/// whichever app registered it first, so ⌥⇥ may open the other app instead.
private struct RivalSwitchersGroup: View {
    let rivals: RivalSwitcherMonitor
    let keycaps: [String]

    var body: some View {
        SettingsGroup(footer: "Two switchers can't share a shortcut. Quit the other one, or pick a different shortcut in either app.") {
            ForEach(rivals.runningNames, id: \.self) { name in
                SettingsRow(title: "\(name) is also running",
                            subtitle: "Pressing \(keycaps.joined()) may open \(name) instead of Spanner.",
                            symbol: "exclamationmark.triangle.fill", tint: .orange) {
                    Button("Quit \(name)") { rivals.quit(name) }
                }
            }
        }
    }
}

private struct ShortcutGroup: View {
    @Bindable var settings: SwitcherSettings
    let shortcutUnavailable: Bool

    var body: some View {
        SettingsGroup(title: "Shortcut", footer: footer) {
            SettingsRow(title: "All windows",
                        subtitle: "Hold the modifier, tap Tab to move, release to switch. Arrow keys and Esc work while it's open.",
                        symbol: "rectangle.on.rectangle", tint: FeatureTint.switcher) {
                HStack(spacing: Spacing.m) {
                    Keycaps(keys: settings.trigger.keycaps)
                        .animation(.spanner, value: settings.trigger)
                    Picker("Shortcut", selection: $settings.trigger) {
                        ForEach(SwitcherTrigger.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsRow(title: "Windows of the current app",
                        subtitle: "Cycle only the frontmost app's windows.",
                        symbol: "macwindow.on.rectangle", tint: .indigo) {
                HStack(spacing: Spacing.m) {
                    Keycaps(keys: settings.trigger.appWindowsKeycaps)
                        .opacity(settings.appWindowsEnabled ? 1 : 0.4)
                    Toggle("Windows of the current app", isOn: $settings.appWindowsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    private var footer: String? {
        if shortcutUnavailable {
            return "Another app is already using this shortcut. Choose a different one, or quit the other app."
        }
        if settings.trigger.replacesSystemSwitcher {
            return "Command-Tab replaces the macOS app switcher while Spanner runs. Spanner gives it back when you quit or change this setting, and on its next launch if it ever quits unexpectedly."
        }
        return nil
    }
}
