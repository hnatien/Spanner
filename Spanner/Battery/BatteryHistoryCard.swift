import Charts
import SpannerCore
import SwiftUI

/// Charge level over the last 1, 6 or 24 hours, with charging periods
/// shaded. History is recorded while Spanner runs and kept for a day.
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
    }

    @State private var range: Range = .sixHours

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardTitle(title: "History", symbol: "chart.xyaxis.line")
                    Spacer()
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    chart(now: context.date)
                }
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private func chart(now: Date) -> some View {
        let samples = history.samples(within: range.seconds, now: now)
        if samples.count < 2 {
            EmptyStateView(symbol: "chart.xyaxis.line",
                           title: "Collecting data",
                           message: "History builds up minute by minute while Spanner is running.")
        } else {
            let runs = ChargeHistory.chargingRuns(in: samples)
            Chart {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    RectangleMark(xStart: .value("Start", run.lowerBound),
                                  xEnd: .value("End", run.upperBound),
                                  yStart: .value("Bottom", 0),
                                  yEnd: .value("Top", 100))
                        .foregroundStyle(.green.opacity(0.1))
                }
                ForEach(samples) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: now.addingTimeInterval(-range.seconds)...now)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .accessibilityLabel("Charge history")
            .accessibilityValue(accessibilitySummary(samples))
        }
    }

    private func accessibilitySummary(_ samples: [ChargeSample]) -> String {
        guard let first = samples.first, let last = samples.last else { return "" }
        return "From \(first.percent) percent to \(last.percent) percent over the last \(range.rawValue)"
    }
}
