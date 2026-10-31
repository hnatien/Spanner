import SwiftUI

/// First-launch guide: what Spanner does, the two permissions the switcher
/// needs (granted live, with status updating as the person flips switches),
/// and how to use it.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, permissions, ready
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: WelcomeStep()
                case .permissions: PermissionsStep()
                case .ready: ReadyStep()
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.xxl + Spacing.s)
            .padding(.top, Spacing.xxl + Spacing.l)

            controls
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xl)
        }
        .frame(width: 600, height: 560)
        .background(alignment: .top) {
            LinearGradient(colors: [Color.accentColor.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .animation(.spanner, value: step)
    }

    private var controls: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(-1) }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            StepDots(count: Step.allCases.count, current: step.rawValue)
            Spacer()
            Button(step == .ready ? "Start Using Spanner" : "Continue") {
                if step == .ready { finish() } else { go(1) }
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func finish() {
        hasCompletedOnboarding = true
        dismissWindow(id: WindowID.onboarding)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                Text("Welcome to Spanner")
                    .font(.largeTitle.weight(.bold))
                Text("A small set of tools that make your Mac feel a little more yours.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: Spacing.l) {
                FeatureLine(section: .switcher,
                            text: "See every window, on every screen and Space, with live previews.")
                FeatureLine(section: .battery,
                            text: "Health, power flow and charger details at a glance.")
                FeatureLine(section: .keepAwake,
                            text: "Keep your Mac awake for as long as you need.")
            }
            .frame(maxWidth: 440)
        }
    }
}

private struct FeatureLine: View {
    let section: AppSection
    let text: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            SymbolTile(symbol: section.symbol, tint: section.tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionsStep: View {
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Two permissions for the window switcher")
                    .font(.title.weight(.bold))
                Text("macOS asks you to approve these in System Settings. Spanner notices the moment you do. You can skip this and grant them later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup {
                ForEach(Permission.allCases) { PermissionRow(permission: $0) }
            }
            if permissions.allGranted {
                Label("All set. The switcher is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else {
                Label("Battery and Keep Awake work without any permissions.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.spanner, value: permissions.allGranted)
    }
}

private struct ReadyStep: View {
    @Environment(SwitcherController.self) private var switcher

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
            VStack(spacing: Spacing.s) {
                Text("You're all set").font(.largeTitle.weight(.bold))
                Text("Spanner lives in your menu bar. Click the wrench any time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Card(padding: Spacing.l) {
                HStack(spacing: Spacing.l) {
                    Keycaps(keys: switcher.triggerKeycaps)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch windows").font(.headline)
                        Text("Hold the first key, tap the second to move, release to switch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 440)
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
