import AppKit
import SpannerCore
import SwiftUI

/// Apps ranked by the power they draw right now, with energy used since
/// Spanner started. Processes no app accounts for share one row at the end.
struct EnergyCard: View {
    @Environment(EnergyMonitor.self) private var energy
    @Environment(\.appearsActive) private var appearsActive
    @State private var showsAll = false

    private static let collapsedCount = 6

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardTitle(title: "Energy by app")
                    Spacer()
                    if let last = energy.lastSample {
                        Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if energy.apps.isEmpty && energy.background == nil {
                    Text("Measuring…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let shown = showsAll ? energy.apps.prefix(25) : energy.apps.prefix(Self.collapsedCount)
                    let peak = max(energy.apps.first?.watts ?? 0, energy.background?.watts ?? 0, 0.001)
                    VStack(spacing: Spacing.s) {
                        ColumnHeader()
                        ForEach(shown) { app in
                            EnergyRow(icon: Image(nsImage: NSWorkspace.shared.icon(forFile: app.groupKey)), name: app.name,
                                      watts: app.watts, joules: app.joules, fraction: app.watts / peak)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if let background = energy.background {
                            Divider()
                            EnergyRow(icon: Image(systemName: "gearshape.2"), name: "Background processes",
                                      detail: Self.summary(of: background.names),
                                      watts: background.watts, joules: background.joules,
                                      fraction: background.watts / peak, tint: .secondary)
                                .help(background.names.joined(separator: ", "))
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
                Text("Each app includes the helpers and services working for it, from macOS's per-process energy counters. Processes owned by root, like WindowServer, can't be measured.")
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

    /// The count, then the busiest names, so truncation only trims names.
    /// The full list is in the row's tooltip.
    private static func summary(of names: [String]) -> String {
        names.count == 1 ? names[0] : "\(names.count) processes · \(names.prefix(3).joined(separator: ", "))"
    }
}

/// Labels the two figures so the columns read without hovering.
private struct ColumnHeader: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            Spacer()
            Text("Now")
                .frame(width: EnergyRow.valueWidth, alignment: .trailing)
            Text("Total")
                .frame(width: EnergyRow.valueWidth, alignment: .trailing)
                .help("Energy used since Spanner started")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
}

private struct EnergyRow: View {
    static let valueWidth: CGFloat = 64

    let icon: Image
    let name: String
    var detail: String?
    let watts: Double
    let joules: Double
    let fraction: Double
    var tint: Color = FeatureTint.battery

    var body: some View {
        HStack(spacing: Spacing.m) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 170, alignment: .leading)
            MeterBar(fraction: fraction, tint: tint)
            Text(powerText)
                .font(.callout.monospacedDigit())
                .contentTransition(.numericText(value: watts))
                .frame(width: Self.valueWidth, alignment: .trailing)
            Text(energyText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: joules))
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Most apps draw well under a watt, so small values are in milliwatts.
    private var powerText: String {
        watts >= 1 ? BatteryFormat.watts(watts) : String(format: "%.0f mW", watts * 1000)
    }

    private var energyText: String {
        let wattHours = joules / 3600
        return wattHours >= 1 ? String(format: "%.1f Wh", wattHours) : String(format: "%.0f mWh", wattHours * 1000)
    }
}
