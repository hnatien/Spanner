import SpannerCore
import SwiftUI

/// Main-window page for Keep Awake.
struct KeepAwakePage: View {
    @Environment(KeepAwakeController.self) private var keepAwake

    var body: some View {
        @Bindable var keepAwake = keepAwake
        Page {
            PageHeader(title: "Keep Awake",
                       subtitle: "Stop your Mac from going to sleep while you download, present or run long jobs.",
                       symbol: AppSection.keepAwake.symbol, tint: FeatureTint.keepAwake) {
                Toggle("Keep awake", isOn: Binding(get: { keepAwake.isActive },
                                                   set: { $0 ? keepAwake.start(keepAwake.defaultDuration) : keepAwake.stop() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }

            KeepAwakeStatusCard()

            SettingsGroup(title: "Start a session") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3), spacing: Spacing.s) {
                    ForEach(KeepAwakeDuration.allCases) { duration in
                        DurationButton(duration: duration)
                    }
                }
            }

            SettingsGroup(title: "Options",
                          footer: "Your Mac can still sleep when you close the lid or choose Sleep from the Apple menu.") {
                SettingsRow(title: "Keep the display on",
                            subtitle: "Otherwise the screen may dim and turn off, but apps keep running.",
                            symbol: "display", tint: .blue) {
                    Toggle("Keep the display on", isOn: $keepAwake.keepsDisplayOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Menu bar click starts",
                            subtitle: "Duration used when you turn Keep Awake on from the menu bar.",
                            symbol: "menubar.rectangle", tint: .gray) {
                    Picker("Menu bar click starts", selection: $keepAwake.defaultDuration) {
                        ForEach(KeepAwakeDuration.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

/// Large status card with a countdown ring while a timed session runs.
private struct KeepAwakeStatusCard: View {
    @Environment(KeepAwakeController.self) private var keepAwake

    var body: some View {
        Card(padding: Spacing.xl) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Spacing.xl) {
                    ring(at: context.date)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(headline(at: context.date))
                            .font(.title3.weight(.semibold))
                            .contentTransition(.numericText())
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let error = keepAwake.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }
            }
        }
        .animation(.spanner, value: keepAwake.isActive)
    }

    private func ring(at now: Date) -> some View {
        let progress = keepAwake.session?.progress(at: now)
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: keepAwake.isActive ? 1 - (progress ?? 0) : 0)
                .stroke(FeatureTint.keepAwake.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: keepAwake.isActive ? "cup.and.heat.waves.fill" : "moon.zzz.fill")
                .font(.system(size: 26))
                .foregroundStyle(keepAwake.isActive ? FeatureTint.keepAwake : .secondary)
                .symbolEffect(.pulse, isActive: keepAwake.isActive)
        }
        .frame(width: 72, height: 72)
    }

    private func headline(at now: Date) -> String {
        guard let session = keepAwake.session else { return "Your Mac can sleep normally" }
        if let remaining = session.remaining(at: now) {
            return "Awake for \(SpannerFormat.countdown(remaining))"
        }
        return "Awake until you turn it off"
    }

    private var detail: String {
        guard let session = keepAwake.session else { return "Pick a duration below, or turn it on from the menu bar." }
        let display = session.keepsDisplayOn ? "Display stays on." : "Display may sleep."
        return "Started \(session.start.formatted(date: .omitted, time: .shortened)). \(display)"
    }
}

private struct DurationButton: View {
    @Environment(KeepAwakeController.self) private var keepAwake
    let duration: KeepAwakeDuration

    var body: some View {
        Button {
            keepAwake.start(duration)
        } label: {
            Text(duration.title)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }
}
