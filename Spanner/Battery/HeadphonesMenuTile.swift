import SpannerCore
import SwiftUI

/// Connected headphones in the menu bar panel: name, wear status and a gauge
/// per battery (each bud and the case, or one for single-battery
/// headphones). The panel inserts one tile per device under the Mac's
/// battery when it connects and removes it when it disconnects.
struct HeadphonesMenuTile: View {
    let headphone: HeadphoneBattery
    @State private var hasAppeared = false

    var body: some View {
        PanelSection {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                        HeadphoneGauge(gauge: gauge, appearDelay: 0.3 + Double(index) * 0.06)
                            .frame(maxWidth: .infinity)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spanner, value: gauges.map(\.id))
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headphone.name)
        .accessibilityValue(headphone.summary)
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            SymbolTile(symbol: headphone.symbol, tint: FeatureTint.switcher, size: 28)
                .symbolEffect(.bounce, value: hasAppeared)
            VStack(alignment: .leading, spacing: 1) {
                Text(headphone.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(headphone.isInEar == true ? "Connected · In your ears" : "Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: Spacing.s)
            if let level = headphone.level, level != .normal {
                StatusPill(text: "Low", symbol: "battery.25percent", tint: BatteryStyle.tint(for: level))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spanner, value: headphone.isInEar)
        .animation(.spanner, value: headphone.level)
    }

    private var gauges: [HeadphoneGauge.Model] {
        var gauges: [HeadphoneGauge.Model] = []
        if let left = headphone.left {
            gauges.append(.init(id: "left", label: "Left", symbol: headphone.leftSymbol, percent: left))
        }
        if let right = headphone.right {
            gauges.append(.init(id: "right", label: "Right", symbol: headphone.rightSymbol, percent: right))
        }
        if headphone.left == nil, headphone.right == nil, let single = headphone.single {
            gauges.append(.init(id: "single", label: "Battery", symbol: headphone.symbol, percent: single))
        }
        if let chargingCase = headphone.chargingCase {
            gauges.append(.init(id: "case", label: "Case", symbol: headphone.caseSymbol, percent: chargingCase))
        }
        return gauges
    }
}

/// Ring gauge for one battery. The ring fills up from empty when it first
/// appears; the percentage is shown as is, since rolling digits from zero
/// reads as noise next to the moving ring.
private struct HeadphoneGauge: View {
    struct Model: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let percent: Int
    }

    let gauge: Model
    let appearDelay: Double
    /// Starts at zero so the first appearance animates up to the real level.
    @State private var fill: CGFloat = 0

    private static let size: CGFloat = 44
    private static let lineWidth: CGFloat = 4

    var body: some View {
        let tint = BatteryStyle.tint(for: ChargeLevel(percent: gauge.percent))
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: gauge.symbol)
                    .font(.system(size: Self.size * 0.36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Self.size, height: Self.size)
            Text("\(gauge.percent)%")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(gauge.percent)))
                .animation(.spanner, value: gauge.percent)
            Text(gauge.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9).delay(appearDelay)) {
                fill = CGFloat(gauge.percent) / 100
            }
        }
        .onChange(of: gauge.percent) { _, percent in
            withAnimation(.spanner) { fill = CGFloat(percent) / 100 }
        }
    }
}

extension AnyTransition {
    /// The sections below slide down to make room before the tile fades in,
    /// and it fades out quickly before they slide back over its place, so
    /// two translucent tiles never overlap mid-move.
    static let headphoneTile = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.2))
            .combined(with: .scale(scale: 0.96, anchor: .top)),
        removal: .opacity.animation(.easeIn(duration: 0.08)))
}
