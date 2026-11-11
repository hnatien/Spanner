import SwiftUI

/// One permission with its live status and a button to grant it. Used by the
/// Permissions page, feature pages and onboarding so all behave identically.
struct PermissionRow: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let permission: Permission
    /// Shown instead of the permission's rationale.
    var subtitle: String? = nil
    /// False where no running feature relies on the permission, so the row
    /// is greyed and its button doesn't call for attention.
    var isNeeded = true

    var body: some View {
        let granted = permissions.isGranted(permission)
        let asked = permissions.requested.contains(permission)
        VStack(alignment: .leading, spacing: Spacing.s) {
            SettingsRow(title: permission.title, subtitle: subtitle ?? permission.rationale,
                        symbol: permission.symbol, tint: isNeeded ? FeatureTint.permissions : .gray) {
                if granted {
                    Label {
                        Text("Granted").foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .transition(.opacity)
                } else if asked {
                    action("Open Settings") { permissions.openSettings(for: permission) }
                } else {
                    action("Grant…") { permissions.request(permission) }
                        .transition(.opacity)
                }
            }
            if asked && !granted {
                manualHelp
                    .transition(.opacity)
            }
        }
        .animation(animation, value: granted)
        .animation(animation, value: asked)
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spanner
    }

    @ViewBuilder
    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        if isNeeded {
            Button(title, action: perform).prominentButtonStyle()
        } else {
            Button(title, action: perform)
        }
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
