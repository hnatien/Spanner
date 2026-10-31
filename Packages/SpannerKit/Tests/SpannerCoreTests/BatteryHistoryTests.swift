import Foundation
import Testing
@testable import SpannerCore

@Suite("Charge history")
struct BatteryHistoryTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func sample(_ offset: TimeInterval, _ percent: Int = 50, charging: Bool = false) -> ChargeSample {
        ChargeSample(date: start.addingTimeInterval(offset), percent: percent, isCharging: charging, systemWatts: 10)
    }

    @Test func keepsAtMostOneSamplePerMinute() {
        var history = ChargeHistory()
        let addedFirst = history.record(sample(0))
        #expect(addedFirst)
        let addedTooSoon = history.record(sample(30))
        #expect(!addedTooSoon)
        let addedAfterMinute = history.record(sample(60))
        #expect(addedAfterMinute)
        #expect(history.samples.count == 2)
    }

    @Test func chargingFlipIsRecordedImmediately() {
        var history = ChargeHistory()
        history.record(sample(0, charging: false))
        let addedOnFlip = history.record(sample(5, charging: true))
        #expect(addedOnFlip)
    }

    @Test func rejectsSamplesFromThePast() {
        var history = ChargeHistory()
        history.record(sample(120))
        let addedOutOfOrder = history.record(sample(0))
        #expect(!addedOutOfOrder)
    }

    @Test func trimsToTwentyFourHours() {
        var history = ChargeHistory()
        for minute in 0...(25 * 60) {
            history.record(sample(Double(minute) * 60, minute % 100))
        }
        let newest = history.samples.last!.date
        #expect(history.samples.first!.date >= newest.addingTimeInterval(-ChargeHistory.retention))
        #expect(history.samples.count == 24 * 60 + 1)
    }

    @Test func windowFiltersRecentSamples() {
        var history = ChargeHistory()
        for minute in 0..<180 { history.record(sample(Double(minute) * 60)) }
        let now = start.addingTimeInterval(179 * 60)
        #expect(history.samples(within: 3600, now: now).count == 61)
    }

    @Test func codableRoundTrip() throws {
        var history = ChargeHistory()
        history.record(sample(0, 40, charging: true))
        history.record(sample(60, 41, charging: true))
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(ChargeHistory.self, from: data)
        #expect(decoded == history)
    }

    @Test func initSortsSamples() {
        let history = ChargeHistory(samples: [sample(120), sample(0)])
        #expect(history.samples.map(\.date) == [start, start.addingTimeInterval(120)])
    }

    @Test func chargingRunsSpanUntilUnplug() {
        let samples = [sample(0), sample(60, charging: true), sample(120, charging: true),
                       sample(180), sample(240, charging: true)]
        let runs = ChargeHistory.chargingRuns(in: samples)
        #expect(runs == [start.addingTimeInterval(60)...start.addingTimeInterval(180),
                         start.addingTimeInterval(240)...start.addingTimeInterval(240)])
    }

    @Test func noRunsWhenNeverCharging() {
        #expect(ChargeHistory.chargingRuns(in: [sample(0), sample(60)]).isEmpty)
    }
}
