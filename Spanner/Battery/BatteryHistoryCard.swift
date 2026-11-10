import Charts
import SpannerCore
import SwiftUI

/// Charge level over the last 1, 6 or 24 hours, coloured by whether the Mac
/// was charging, with a summary of the current rate and the last charge.
/// History is recorded while Spanner runs and kept for a day.
struct BatteryHistoryCard: View {
    let history: ChargeHistory

    enum Range: String, CaseIterable, Identifiable {
        case hour = "1 h", sixHours = "6 h", day = "24 h"

        var id: Self { self }
        var seconds: TimeInterval {
            switch self {
            case .hour: 3600
            case .sixHours: 6 * 3600
            case .day: 24 * 3600
            }
        }

        var tickUnit: Calendar.Component { self == .hour ? .minute : .hour }
        var tickCount: Int {
            switch self {
            case .hour: 15
            case .sixHours: 1
            case .day: 4
            }
        }
    }

    private static let chargingColor = Color.green
    private static let drainingColor = Color.accentColor
    private static let noDataColor = Color.secondary.opacity(0.6)
    private static let lowThreshold = 20

    @State private var range: Range = .sixHours
    @State private var selectedDate: Date?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardTitle(title: "History")
                    Spacer()
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let samples = history.samples(within: range.seconds, now: context.date)
                    if samples.count < 2 {
                        EmptyStateView(symbol: "chart.xyaxis.line",
                                       title: "Collecting data",
                                       message: "History builds up minute by minute while Spanner is running.")
                            .frame(height: 180)
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            summary(samples)
                            chart(samples, now: context.date)
                                .frame(height: 180)
                            legend
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private func summary(_ samples: [ChargeSample]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.l, alignment: .topLeading)],
                  alignment: .leading, spacing: Spacing.l) {
            trendTile
            lastChargeTile
            rangeTile(samples)
        }
    }

    private var trendTile: some View {
        guard let trend = history.currentTrend() else {
            return StatTile(title: "Rate", value: "Measuring…", detail: "Needs 15 minutes of data",
                            symbol: "speedometer", tint: .secondary)
        }
        let rate = abs(trend.percentPerHour)
        let value = rate < 0.5
            ? "Steady"
            : "\(rate.formatted(.number.precision(.fractionLength(rate < 10 ? 1 : 0))))% per hour"
        return StatTile(title: trend.isCharging ? "Charging rate" : "Drain rate", value: value,
                        detail: "Over the last \(SpannerFormat.duration(trend.span))",
                        symbol: trend.isCharging ? "arrow.up.right" : "arrow.down.right",
                        tint: trend.isCharging ? Self.chargingColor : Self.drainingColor)
    }

    private var lastChargeTile: some View {
        guard let session = history.lastChargeSession else {
            return StatTile(title: "Last charge", value: "None in 24 h", symbol: "bolt.fill", tint: Self.chargingColor)
        }
        let start = session.start.formatted(date: .omitted, time: .shortened)
        return StatTile(title: session.isOngoing ? "Charging" : "Last charge",
                        value: "\(session.fromPercent)% → \(session.toPercent)%",
                        detail: session.isOngoing
                            ? "Since \(start)"
                            : "\(start), \(SpannerFormat.duration(session.duration))",
                        symbol: "bolt.fill", tint: Self.chargingColor)
    }

    private func rangeTile(_ samples: [ChargeSample]) -> some View {
        let percents = samples.map(\.percent)
        return StatTile(title: "Last \(range.rawValue)",
                        value: "\(percents.first ?? 0)% → \(percents.last ?? 0)%",
                        detail: "Low \(percents.min() ?? 0)%, high \(percents.max() ?? 0)%",
                        symbol: "chart.line.uptrend.xyaxis", tint: .secondary)
    }

    // MARK: - Chart

    private func chart(_ samples: [ChargeSample], now: Date) -> some View {
        let bridged = ChargeHistory.bridgingChargingGaps(in: samples)
        let segments = ChargeHistory.chartSegments(for: samples)
        let selected = selectedDate.flatMap { date in
            bridged.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return Chart {
            RuleMark(y: .value("Low battery", Self.lowThreshold))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if segment.kind == .noData {
                    ForEach(segment.samples) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent),
                                 series: .value("Segment", index))
                            .foregroundStyle(Self.noDataColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
                    }
                } else {
                    let color = color(isCharging: segment.kind == .charging)
                    ForEach(segment.samples) { sample in
                        AreaMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent),
                                 series: .value("Segment", index), stacking: .unstacked)
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent),
                                 series: .value("Segment", index))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }

            if let last = bridged.last {
                PointMark(x: .value("Time", last.date), y: .value("Charge", last.percent))
                    .symbol { endDot(color: color(isCharging: last.isCharging)) }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: Spacing.xs,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(for: selected)
                    }
                PointMark(x: .value("Time", selected.date), y: .value("Charge", selected.percent))
                    .symbol { endDot(color: color(isCharging: selected.isCharging)) }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: now.addingTimeInterval(-range.seconds)...now)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: range.tickUnit, count: range.tickCount)) {
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, Self.lowThreshold, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .accessibilityLabel("Charge history")
        .accessibilityValue(accessibilitySummary(samples))
    }

    private func color(isCharging: Bool) -> Color {
        isCharging ? Self.chargingColor : Self.drainingColor
    }

    private func endDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.background, lineWidth: 2))
    }

    private func tooltip(for sample: ChargeSample) -> some View {
        HStack(spacing: Spacing.s) {
            Text(sample.date.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(.secondary)
            Text("\(sample.percent)%")
                .fontWeight(.semibold)
            Label(sample.isCharging ? "Charging" : "Not charging",
                  systemImage: sample.isCharging ? "bolt.fill" : "battery.75percent")
                .foregroundStyle(color(isCharging: sample.isCharging))
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: .rect(cornerRadius: CornerRadius.s, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: Spacing.l) {
            legendItem("Charging") { Capsule().fill(Self.chargingColor).frame(width: 14, height: 3) }
            legendItem("Not charging") { Capsule().fill(Self.drainingColor).frame(width: 14, height: 3) }
            legendItem("No data") {
                dashSwatch(color: Self.noDataColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            legendItem("Low battery") {
                dashSwatch(color: .red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func dashSwatch(color: Color, style: StrokeStyle) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1.5))
            path.addLine(to: CGPoint(x: 14, y: 1.5))
        }
        .stroke(color, style: style)
        .frame(width: 14, height: 3)
    }

    private func legendItem(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: Spacing.xs) {
            swatch()
            Text(title)
        }
    }

    private func accessibilitySummary(_ samples: [ChargeSample]) -> String {
        guard let first = samples.first, let last = samples.last else { return "" }
        return "From \(first.percent) percent to \(last.percent) percent over the last \(range.rawValue)"
    }
}
