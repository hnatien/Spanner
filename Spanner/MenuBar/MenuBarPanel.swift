import SpannerCore
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
    @Environment(HeadphoneMonitor.self) private var headphones
    @Environment(DisplayController.self) private var displays
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The content's natural height, animated whenever it changes so the
    /// window resizes in step with the sections moving inside it.
    @State private var height: CGFloat?
    /// The headphones on screen. Trails the monitor so connecting and
    /// disconnecting can each pick their own timing.
    @State private var shownHeadphones: [HeadphoneBattery] = []
    /// Animation for the resize that follows a headphone change.
    @State private var pendingResize: Animation?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header

            PanelSection {
                BatteryMenuSummary()
            }
            .onTapGesture { open(.battery) }

            ForEach(shownHeadphones) { headphone in
                HeadphonesMenuTile(headphone: headphone)
                    .transition(reduceMotion ? .opacity : .headphoneTile)
            }

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
        // Never squeezed by the window: the window follows the content.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
            if height == nil {
                height = newHeight
            } else {
                withAnimation(pendingResize ?? resizeAnimation) { height = newHeight }
                pendingResize = nil
            }
        }
        .modifier(AnimatedPanelHeight(height: height))
        .background(MenuBarWindowFitter())
        // Pins the content under the menu bar if the window is ever taller.
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: headphones.headphones) { old, new in
            let oldIDs = Set(old.map(\.id))
            let newIDs = Set(new.map(\.id))
            guard oldIDs != newIDs else {
                // Battery updates: each tile animates its own values.
                shownHeadphones = new
                return
            }
            // A leaving tile fades out (see `headphoneTile`) before the
            // sections below move up over its place.
            let animation = newIDs.isSuperset(of: oldIDs) ? resizeAnimation : resizeAnimation.delay(0.08)
            pendingResize = animation
            withAnimation(animation) { shownHeadphones = new }
        }
        .onAppear {
            shownHeadphones = headphones.headphones
            battery.isDetailedRefresh = true
        }
        .onDisappear { battery.isDetailedRefresh = false }
    }

    private var resizeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9)
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

/// Lays the panel out at an animated height, frame by frame. A plain
/// `.frame(height:)` animates only on screen and lays out at the final
/// height at once; being `Animatable` re-runs layout with each interpolated
/// value, so the window (sized from layout) moves with the content.
private struct AnimatedPanelHeight: ViewModifier, Animatable {
    var height: CGFloat?

    var animatableData: CGFloat {
        get { height ?? 0 }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(height: height, alignment: .top)
    }
}

/// MenuBarExtra's window grows with its content but doesn't shrink back:
/// SwiftUI lowers the window's minimum size and leaves the frame. Placed
/// behind the panel, this view has the panel's laid-out size and fits the
/// window to it on every layout, so an animated height resizes the window
/// each frame, with the top edge kept under the menu bar.
private struct MenuBarWindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FittingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FittingView: NSView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            fitWindow()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fitWindow()
        }

        private func fitWindow() {
            guard let window, let contentView = window.contentView, bounds.height > 0,
                  abs(bounds.height - contentView.frame.height) > 0.5 else { return }
            var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentView.frame.width,
                                                                 height: bounds.height))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
    }
}
