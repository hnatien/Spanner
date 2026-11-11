import SpannerCore
import SwiftUI

/// Main-window page listing every permission with its live status.
/// Permissions that only features turned off rely on are set apart, so the
/// page never pushes a grant nothing would use.
struct PermissionsPage: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(FeatureRegistry.self) private var features

    var body: some View {
        let inUse = Permission.allCases.filter { $0.features.contains(where: features.isEnabled) }
        let unused = Permission.allCases.filter { !inUse.contains($0) }
        Page {
            PageHeader(title: AppSection.permissions.title,
                       subtitle: "What macOS lets Spanner do, and which features rely on it.",
                       symbol: AppSection.permissions.symbol, tint: FeatureTint.permissions)

            if !inUse.isEmpty {
                SettingsGroup(title: "In use", footer: "Nothing Spanner sees or hears leaves your Mac.") {
                    ForEach(inUse) { permission in
                        let users = permission.features.filter(features.isEnabled)
                        PermissionRow(permission: permission,
                                      subtitle: "\(permission.rationale) Used by \(Self.names(of: users)).")
                    }
                }
            }

            if !unused.isEmpty {
                SettingsGroup(title: "Not in use",
                              footer: "You don't need to grant these while the features are off.") {
                    ForEach(unused) { permission in
                        let users = permission.features
                        PermissionRow(permission: permission,
                                      subtitle: "\(Self.names(of: users)) \(users.count == 1 ? "is" : "are") off, so nothing uses this.",
                                      isNeeded: false)
                    }
                }
            }

            SettingsGroup(title: "Troubleshooting") {
                SettingsRow(title: "Granted in System Settings, but missing here?",
                            subtitle: "Remove Spanner from the list in Privacy & Security with the minus button, then grant it again.",
                            symbol: "gear", tint: .gray) {
                    Button("Open Settings") { permissions.openSettings(for: .accessibility) }
                }
            }
        }
    }

    /// "Window Switcher and Window Snapping".
    private static func names(of features: [Feature]) -> String {
        features.map { AppSection($0).title }.formatted(.list(type: .and))
    }
}
