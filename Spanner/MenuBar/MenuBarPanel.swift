import SwiftUI

/// The status item icon. Fills in while Keep Awake is on, so its state is
/// visible without opening the panel.
struct MenuBarIcon: View {
    @Environment(KeepAwakeController.self) private var keepAwake
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Image(systemName: keepAwake.isActive ? "wrench.adjustable.fill" : "wrench.adjustable")
            .accessibilityLabel("Spanner")
            .task {
                // The label is the first view macOS renders, so first-launch
                // onboarding is opened from here.
                if !hasCompletedOnboarding {
                    openWindow(id: WindowID.onboarding)
                }
            }
    }
}

/// Content of the menu bar window: glanceable status plus the most common
/// actions, each one click away.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(PermissionsManager.self) private var permissions
    @Environment(BatteryService.self) private var battery
    @Environment(DisplayController.self) private var displays
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header

            PanelSection {
                BatteryMenuSummary()
            }
            .onTapGesture { open(.battery) }

            PanelSection {
                VStack(spacing: Spacing.m) {
                    KeepAwakeMenuRow()
                    Divider()
                    SwitcherMenuRow()
                }
            }

            if displays.displays.contains(where: \.hasDDC) {
                PanelSection {
                    DisplaysMenuSection()
                }
            }

            if !permissions.allGranted {
                permissionsBanner
            }

            footer
        }
        .padding(Spacing.m)
        .frame(width: 340)
        .onAppear { battery.isDetailedRefresh = true }
        .onDisappear { battery.isDetailedRefresh = false }
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wrench.adjustable.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Spanner").font(.headline)
            Spacer()
            Button {
                open(.general)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, Spacing.xs)
    }

    private var permissionsBanner: some View {
        PanelSection(tint: .orange) {
            HStack(spacing: Spacing.m) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Permission needed").font(.callout.weight(.medium))
                    Text("The window switcher can't see your windows yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s)
                Button("Fix") { open(.permissions) }
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Spanner") { open(.battery) }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, Spacing.xs)
    }

    private func open(_ section: AppSection) {
        model.selectedSection = section
        // Close the panel so it doesn't sit over the window it just opened.
        dismiss()
        openWindow(id: WindowID.main)
        // If the window is already open, onAppear won't fire again, so
        // DockPresence never activates the app and the window stays behind
        // whatever app is frontmost.
        NSApp.activate()
    }
}

/// Rounded tile grouping related controls inside the menu bar panel. The
/// panel itself is glass on macOS 26, so tiles use a quiet fill.
struct PanelSection<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(.quinary),
                        in: .rect(cornerRadius: CornerRadius.m, style: .continuous))
            .contentShape(.rect)
    }
}
