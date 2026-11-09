import Charts
import SpannerCore
import SwiftUI

/// Colours for load gauges: each metric keeps its own hue until it runs
/// hot, then turns orange and red so trouble stands out at a glance.
enum SystemStyle {
    static let cpu = Color.blue
    static let gpu = Color.purple
    static let memory = Color.teal
    static let received = Color.cyan
    static let sent = Color.indigo
    static let read = Color.green
    static let written = Color.pink
    static let disk = Color.gray

    static func tint(load: Double, base: Color) -> Color {
        load >= 0.95 ? .red : load >= 0.8 ? .orange : base
    }

    /// Memory is coloured by pressure, not fill: a full but healthy cache is
    /// normal on macOS, while pressure means apps are being slowed down.
    static func tint(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: memory
        case .warning: .orange
        case .critical: .red
        }
    }

    static func label(for pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    /// Serious and Critical mean macOS is slowing the chip down to cool it,
    /// so they say so instead of only naming the level.
    static func label(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Thermal: Nominal"
        case .fair: "Thermal: Fair"
        case .serious: "Throttling: Serious"
        case .critical: "Throttling: Critical"
        @unknown default: "Thermal: Unknown"
        }
    }

    static func tint(for state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .secondary
        }
    }

    static func symbol(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        @unknown default: "thermometer.medium"
        }
    }
}

/// Circular load gauge with the percentage in the middle. Plain shapes, no
/// Canvas or timeline: it redraws only when its value changes.
struct LoadRing: View {
    /// 0...1, or nil while the first reading is pending.
    let fraction: Double?
    let tint: Color
    var size: CGFloat = 46
    /// Springs to each new value. The System page turns this off: there,
    /// every animation frame re-lays out the whole page, and a spring every
    /// two seconds kept the window rendering most of the time.
    var animated = true

    var body: some View {
        let lineWidth = size * 0.11
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction.map(SpannerFormat.percent) ?? "–")
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: fraction ?? 0))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, lineWidth)
        }
        .frame(width: size, height: size)
        .animation(animated ? .spanner : nil, value: fraction)
    }
}

/// Horizontal bar split into proportional coloured segments, with the
/// remainder of `total` left empty. Laid out by `ProportionalStack`, so it
/// needs no GeometryReader. It doesn't animate: it's redrawn with live
/// values every few seconds, and each animation frame costs a page layout.
struct StackedBar: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let total: Double
    var height: CGFloat = 10

    var body: some View {
        ProportionalStack(spacing: 1.5) {
            ForEach(segments) { segment in
                Rectangle()
                    .fill(segment.color.gradient)
                    .layoutValue(key: ProportionalStack.Fraction.self,
                                 value: total > 0 ? min(1, max(0, segment.value / total)) : 0)
            }
        }
        .frame(height: height)
        .background(.quaternary)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}

/// Places children left to right, each as wide as its `Fraction` of the
/// container minus the spacing that follows it.
struct ProportionalStack: Layout {
    struct Fraction: LayoutValueKey {
        static let defaultValue: Double = 0
    }

    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 0, height: 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let fraction = subview[Fraction.self]
            let width = max(0, bounds.width * fraction - spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            if fraction > 0 { x += width + spacing }
        }
    }
}

/// Stat tiles in one row when they fit at their natural width, otherwise
/// two per row, so a narrow window reflows them instead of shrinking or
/// truncating the numbers.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.l) { content }
            Group(subviews: content) { subviews in
                Grid(alignment: .topLeading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.m) {
                    ForEach(Array(stride(from: 0, to: subviews.count, by: 2)), id: \.self) { start in
                        GridRow {
                            subviews[start]
                            if start + 1 < subviews.count { subviews[start + 1] }
                        }
                    }
                }
            }
        }
    }
}

/// The last two minutes of a two-way rate (download and upload, read and
/// write) as two lines. The scale follows the busier direction, with a
/// 1 KB/s floor so an idle link doesn't magnify background chatter into
/// mountains. Animations are off, as in `LoadChart`.
struct RateChart: View {
    struct Series {
        let title: String
        let history: MetricHistory
        let tint: Color
    }

    let inbound: Series
    let outbound: Series

    private static let minimumScale = 1_000.0

    var body: some View {
        let peak = max(inbound.history.values.max() ?? 0, outbound.history.values.max() ?? 0, Self.minimumScale)
        Group {
            if inbound.history.count < 2 {
                Text("Collecting data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(inbound.history.samples) { sample in
                        AreaMark(x: .value("Time", sample.id), y: .value("Rate", sample.value),
                                 series: .value("Direction", inbound.title))
                            .foregroundStyle(inbound.tint.opacity(0.18).gradient)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", sample.id), y: .value("Rate", sample.value),
                                 series: .value("Direction", inbound.title))
                            .foregroundStyle(inbound.tint)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(outbound.history.samples) { sample in
                        LineMark(x: .value("Time", sample.id), y: .value("Rate", sample.value),
                                 series: .value("Direction", outbound.title))
                            .foregroundStyle(outbound.tint)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXScale(domain: inbound.history.idDomain)
                .chartYScale(domain: 0...(peak * 1.1))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, peak / 2, peak]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let rate = value.as(Double.self) { Text(SpannerFormat.rate(rate)) }
                        }
                    }
                }
                .chartLegend(.hidden)
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last two minutes")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let inboundNow = inbound.history.last, let outboundNow = outbound.history.last else {
            return "Collecting data"
        }
        return "\(inbound.title) \(SpannerFormat.rate(inboundNow)), \(outbound.title) \(SpannerFormat.rate(outboundNow))"
    }
}
