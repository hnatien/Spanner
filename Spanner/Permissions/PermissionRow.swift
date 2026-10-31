import SwiftUI

/// One permission with its live status and a button to grant it. Used by the
/// Permissions page and onboarding so both behave identically.
struct PermissionRow: View {
    @Environment(PermissionsManager.self) private var permissions
    let permission: Permission

    var body: some View {
        let granted = permissions.isGranted(permission)
        let asked = permissions.requested.contains(permission)
        VStack(alignment: .leading, spacing: Spacing.s) {
            SettingsRow(title: permission.title, subtitle: permission.rationale,
                        symbol: permission.symbol, tint: granted ? .green : FeatureTint.permissions) {
                if granted {
                    StatusPill(text: "Granted", symbol: "checkmark.circle.fill", tint: .green)
                        .transition(.scale.combined(with: .opacity))
                } else if asked {
                    Button("Open Settings") { permissions.openSettings(for: permission) }
                        .prominentButtonStyle()
                        .controlSize(.small)
                } else {
                    Button("Grant…") { permissions.request(permission) }
                        .prominentButtonStyle()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            if asked && !granted {
                manualHelp
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spanner, value: granted)
        .animation(.spanner, value: asked)
    }

    private var manualHelp: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Turn on Spanner under \(permission.title) in Privacy & Security. Not listed? Click + below the list and choose Spanner.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            Button("Show Spanner in Finder") { permissions.revealAppInFinder() }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.leading, 24 + Spacing.m)
    }
}

/// "Permissions needed" group shown at the top of a module's page while
/// any permission it relies on is missing. Renders nothing once granted.
struct MissingPermissionsGroup: View {
    @Environment(PermissionsManager.self) private var permissions
    let needed: [Permission]
    let footer: String

    var body: some View {
        let missing = needed.filter { !permissions.isGranted($0) }
        if !missing.isEmpty {
            SettingsGroup(title: "Permissions needed", footer: footer) {
                ForEach(missing) { PermissionRow(permission: $0) }
            }
        }
    }
}
