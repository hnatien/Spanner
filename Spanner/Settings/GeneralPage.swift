import SwiftUI

struct GeneralPage: View {
    @Environment(LoginItemController.self) private var loginItem
    @Environment(UpdatesController.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Page {
            PageHeader(title: "General", subtitle: "Startup, headphones, updates and information about Spanner.",
                       symbol: AppSection.general.symbol, tint: FeatureTint.general)

            SettingsGroup(title: "Startup",
                          footer: loginItem.needsApproval ? "macOS needs your approval in Login Items before Spanner can open at login." : nil) {
                SettingsRow(title: "Open Spanner at login", symbol: "power", tint: .green) {
                    Toggle("Open Spanner at login",
                           isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if loginItem.needsApproval {
                    SettingsRow(title: "Approval needed", symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        Button("Open Login Items") { loginItem.openLoginItemsSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            HeadphonesGroup()

            UpdatesGroup()

            SettingsGroup(title: "About") {
                SettingsRow(title: "Version", symbol: "info.circle.fill", tint: .blue) {
                    Text(updates.currentVersion)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                SettingsRow(title: "Welcome guide", subtitle: "Walk through features and permissions again.",
                            symbol: "sparkles", tint: .purple) {
                    Button("Show") { openWindow(id: WindowID.onboarding) }
                }
            }
        }
        .onAppear(perform: loginItem.refresh)
    }
}

private struct HeadphonesGroup: View {
    @Environment(HeadphoneMonitor.self) private var headphones
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        @Bindable var headphones = headphones
        let granted = permissions.isGranted(.bluetooth)
        SettingsGroup(title: "Headphones",
                      footer: granted
                          ? "Connected AirPods and headphones appear in the menu bar panel with their battery. Nothing leaves your Mac."
                          : "Grant Bluetooth to see your AirPods' and headphones' battery in the menu bar panel. Nothing leaves your Mac.") {
            if !granted {
                PermissionRow(permission: .bluetooth)
            }
            SettingsRow(title: "Show battery when you put them on",
                        subtitle: "Pops up on screen when you put your AirPods in, or when other headphones connect.",
                        symbol: "airpods.pro", tint: FeatureTint.switcher) {
                Toggle("Show battery when you put them on", isOn: $headphones.showsHUD)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!granted)
            }
        }
        .animation(.spanner, value: granted)
    }
}

private struct UpdatesGroup: View {
    @Environment(UpdatesController.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        SettingsGroup(title: "Updates",
                      footer: updates.isConfigured ? nil : "This build has no update feed configured, so it won't check for updates.") {
            SettingsRow(title: "Check for updates automatically", symbol: "arrow.triangle.2.circlepath",
                        tint: FeatureTint.updates) {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!updates.isConfigured)
            }
            SettingsRow(title: "Check now", symbol: "arrow.down.circle.fill", tint: FeatureTint.updates) {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.isConfigured || !updates.canCheckForUpdates)
            }
        }
    }
}
