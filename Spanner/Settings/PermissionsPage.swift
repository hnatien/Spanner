import SwiftUI

struct PermissionsPage: View {
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        Page {
            PageHeader(title: "Permissions",
                       subtitle: "Spanner asks only for what its features need. Everything else works without them.",
                       symbol: AppSection.permissions.symbol, tint: FeatureTint.permissions) {
                if permissions.allGranted {
                    StatusPill(text: "All set", symbol: "checkmark.seal.fill", tint: .green)
                }
            }

            SettingsGroup(title: "Window Switcher",
                          footer: "Keep Awake and the Mac's battery need no permissions; headphone battery needs Bluetooth. Spanner never sends anything off your Mac.") {
                ForEach(Permission.allCases) { PermissionRow(permission: $0) }
            }

            SettingsGroup(title: "Troubleshooting",
                          footer: "If a switch is on but Spanner still says it's missing, remove Spanner from the list with the minus button and grant it again. This can happen after updating a development build.") {
                SettingsRow(title: "Open Privacy & Security", symbol: "gear", tint: .gray) {
                    Button("Open") { permissions.openSettings(for: .accessibility) }
                }
            }
        }
    }
}
