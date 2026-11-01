import AppKit
import SpannerCore
import SwiftUI

/// Apps ranked by the power they draw right now, with energy used since
/// Spanner started.
struct EnergyCard: View {
    @Environment(EnergyMonitor.self) private var energy
    @Environment(\.appearsActive) private var appearsActive
    @State private var showsAll = false

    private static let collapsedCount = 6

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardTitle(title: "Energy by app", symbol: "bolt.fill")
                    Spacer()
                    if let last = energy.lastSample {
                        Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if energy.apps.isEmpty {
                    Text("Measuring…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let shown = showsAll ? energy.apps.prefix(25) : energy.apps.prefix(Self.collapsedCount)
                    let peak = max(energy.apps.first?.watts ?? 0, 0.001)
                    VStack(spacing: Spacing.s) {
                        ForEach(shown) { app in
                            EnergyRow(app: app, fraction: app.watts / peak)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    // Animate each sample as one transaction so re-ranked rows
                    // slide together with their bars instead of the bars
                    // springing on their own while the labels jump.
                    .animation(.spanner, value: energy.apps)
                    if energy.apps.count > Self.collapsedCount {
                        Button(showsAll ? "Show Less" : "Show More") {
                            withAnimation(.spanner) { showsAll.toggle() }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
                Text("Your apps and their helpers, from macOS's per-process energy counters. System processes owned by root aren't included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Like the battery dashboard, sample fast only while the window is in
        // the active app.
        .onAppear { energy.isVisible = appearsActive }
        .onChange(of: appearsActive) { _, active in energy.isVisible = active }
        .onDisappear { energy.isVisible = false }
    }
}

private struct EnergyRow: View {
    let app: AppPower
    let fraction: Double

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(app.name)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            MeterBar(fraction: fraction, tint: FeatureTint.battery)
            Text(powerText)
                .font(.callout.monospacedDigit())
                .contentTransition(.numericText(value: app.watts))
                .frame(width: 64, alignment: .trailing)
            Text(energyText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: app.joules))
                .frame(width: 64, alignment: .trailing)
                .help("Energy used since Spanner started")
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: NSImage {
        app.groupKey.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: app.groupKey)
            : NSWorkspace.shared.icon(for: .unixExecutable)
    }

    /// Most apps draw well under a watt, so small values are in milliwatts.
    private var powerText: String {
        app.watts >= 1 ? BatteryFormat.watts(app.watts) : String(format: "%.0f mW", app.watts * 1000)
    }

    private var energyText: String {
        let wattHours = app.joules / 3600
        return wattHours >= 1 ? String(format: "%.1f Wh", wattHours) : String(format: "%.0f mWh", wattHours * 1000)
    }
}
