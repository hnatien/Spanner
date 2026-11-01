import SpannerCore
import SwiftUI

/// Compact battery summary for the menu bar panel: ring, percentage, status
/// and live watts. The panel opens the dashboard when it's clicked.
struct BatteryMenuSummary: View {
    @Environment(BatteryService.self) private var battery

    var body: some View {
        if let snapshot = battery.snapshot {
            content(snapshot)
        } else if battery.hasBattery == false {
            Label("No battery in this Mac", systemImage: "powerplug.portrait")
                .foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }

    private func content(_ snapshot: BatterySnapshot) -> some View {
        let tint = BatteryStyle.tint(for: snapshot)
        // Percentage, status and watts stack in one leading-aligned column so
        // each line gets the full text width and the watts never wrap.
        return HStack(spacing: Spacing.m) {
            BatteryRing(percent: snapshot.percent, tint: tint, isCharging: snapshot.isCharging, size: 54)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(snapshot.percent)%")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(snapshot.percent)))
                Text(snapshot.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let flow = battery.flow, flow.adapterWatts != nil || flow.systemWatts != nil {
                    HStack(spacing: Spacing.m) {
                        if let adapter = flow.adapterWatts {
                            wattsLine(symbol: "powerplug.portrait.fill", text: "\(BatteryFormat.watts(adapter)) in", tint: .yellow)
                        }
                        if let system = flow.systemWatts {
                            wattsLine(symbol: "laptopcomputer", text: "\(BatteryFormat.watts(system)) use", tint: FeatureTint.switcher)
                        }
                    }
                    .padding(.top, Spacing.xxs)
                }
            }
            // Without priority the HStack splits the free width between this
            // column and the Spacer, wrapping the status text at half width.
            .layoutPriority(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .animation(.spanner, value: snapshot.percent)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the battery dashboard")
    }

    private func wattsLine(symbol: String, text: String, tint: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
    }
}
