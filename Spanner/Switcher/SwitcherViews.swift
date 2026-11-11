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
                       subtitle: "Switch between windows, not just apps, across every screen and Space.",
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

            // The settings stay visible while the switcher is off, but can't
            // be changed until it's back on.
            Group {
                ShortcutGroup(settings: settings, shortcutUnavailable: switcher.shortcutUnavailable)

                SettingsGroup(title: "Show in the switcher") {
                    SettingsRow(title: "Minimized windows") {
                        Toggle("Show minimized windows", isOn: $settings.includeMinimized)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "Windows on other Spaces",
                                subtitle: "Including windows of hidden apps.") {
                        Toggle("Show windows on other Spaces", isOn: $settings.includeOtherSpaces)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                SettingsGroup(title: "Appearance") {
                    SettingsRow(title: "Preview size") {
                        Picker("Preview size", selection: $settings.thumbnailSize) {
                            ForEach(ThumbnailSize.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow(title: "Show switcher on") {
                        Picker("Show switcher on", selection: $settings.overlayScreen) {
                            ForEach(OverlayScreen.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .disabled(!settings.isEnabled)
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
                        subtitle: "Tap Tab to move along and release to switch. Arrow keys and Esc work too.") {
                Picker("Shortcut", selection: $settings.trigger) {
                    ForEach(SwitcherTrigger.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(title: "Windows of the current app",
                        subtitle: "Cycles only through the frontmost app's windows.") {
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
            return "Command-Tab opens Spanner instead of the macOS app switcher. macOS gets it back when you quit Spanner or pick another shortcut."
        }
        return nil
    }
}
