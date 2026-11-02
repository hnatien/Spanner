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

    @Test func shortChargingPausesAreBridged() {
        let samples = [sample(0, charging: true), sample(60), sample(120), sample(180, charging: true)]
        let bridged = ChargeHistory.bridgingChargingGaps(in: samples)
        #expect(bridged.allSatisfy { $0.isCharging })
    }

    @Test func longChargingPausesAndTrailingStretchesStay() {
        let samples = [sample(0, charging: true), sample(60), sample(10 * 60), sample(11 * 60, charging: true),
                       sample(12 * 60)]
        let bridged = ChargeHistory.bridgingChargingGaps(in: samples)
        #expect(bridged.map(\.isCharging) == [true, false, false, true, false])
    }

    @Test func smoothingTurnsStaircaseIntoOnePointPerLevel() {
        // 50% for three minutes, 49% for three, 48% for three.
        let samples = (0..<9).map { sample(Double($0) * 60, 50 - $0 / 3) }
        let points = ChargeHistory.smoothed(samples)
        #expect(points.map(\.percent) == [50, 50, 49, 48, 48])
        #expect(points.map { $0.date.timeIntervalSince(start) } == [0, 60, 240, 420, 480])
    }

    @Test func smoothingKeepsBothEndsOfALongHold() {
        let samples = [sample(0, 60)] + (1...20).map { sample(Double($0) * 60, 80) } + [sample(21 * 60, 79)]
        let points = ChargeHistory.smoothed(samples)
        #expect(points.map { $0.date.timeIntervalSince(start) } == [0, 60, 20 * 60, 21 * 60])
    }

    @Test func smoothingSplitsLevelsOnChargingChange() {
        let samples = [sample(0, 50), sample(60, 50), sample(120, 50, charging: true), sample(180, 50, charging: true)]
        let points = ChargeHistory.smoothed(samples)
        #expect(points.map(\.isCharging) == [false, false, true, true])
    }

    @Test func smoothingLeavesTinyInputsAlone() {
        let samples = [sample(0), sample(60)]
        #expect(ChargeHistory.smoothed(samples) == samples)
        #expect(ChargeHistory.smoothed([]).isEmpty)
    }

    @Test func segmentsShareTheirJoiningSample() {
        let samples = [sample(0), sample(60), sample(120, charging: true), sample(180)]
        let segments = ChargeHistory.segments(of: samples)
        #expect(segments.map(\.kind) == [.notCharging, .charging, .notCharging])
        #expect(segments.map { $0.samples.map { $0.date.timeIntervalSince(start) } }
                == [[0, 60], [60, 120], [120, 180]])
    }

    @Test func chartSegmentsMarkHolesInTheRecording() {
        // Charging, then 40 minutes with no samples, then on battery.
        let samples = [sample(0, 50, charging: true), sample(60, 51, charging: true),
                       sample(41 * 60, 60), sample(42 * 60, 59)]
        let segments = ChargeHistory.chartSegments(for: samples)
        #expect(segments.map(\.kind) == [.charging, .noData, .notCharging])
        #expect(segments[1].samples.map { $0.date.timeIntervalSince(start) } == [60, 41 * 60])
    }

    @Test func chartSegmentsWithoutHolesMatchPlainSegments() {
        let samples = [sample(0, 50), sample(60, 49), sample(120, 49, charging: true), sample(180, 50, charging: true)]
        #expect(ChargeHistory.chartSegments(for: samples)
                == ChargeHistory.segments(of: ChargeHistory.smoothed(samples)))
        #expect(ChargeHistory.chartSegments(for: []).isEmpty)
    }

    @Test func briefStateAfterAHoleTakesTheFollowingState() {
        // Wakes not charging, starts charging a minute later.
        let samples = [sample(0, 60), sample(40 * 60, 69), sample(41 * 60, 69, charging: true),
                       sample(42 * 60, 70, charging: true)]
        let segments = ChargeHistory.chartSegments(for: samples)
        #expect(segments.map(\.kind) == [.notCharging, .noData, .charging])
    }

    @Test func settledStateAfterAHoleStays() {
        let samples = [sample(0, 69), sample(60, 69), sample(180, 69), sample(240, 70, charging: true)]
        #expect(ChargeHistory.settlingStart(of: samples) == samples)
    }

    @Test func trendMeasuresTheCurrentStretch() throws {
        var history = ChargeHistory()
        history.record(sample(0, 20, charging: true))
        for minute in 1...30 { history.record(sample(Double(minute) * 60, 60 - minute / 3)) }
        let trend = try #require(history.currentTrend())
        #expect(!trend.isCharging)
        #expect(trend.span == 29 * 60)
        #expect(abs(trend.percentPerHour - -20.69) < 0.01)
    }

    @Test func trendUsesOnlyTheRecentWindow() throws {
        var history = ChargeHistory()
        for minute in 0...120 { history.record(sample(Double(minute) * 60, minute <= 60 ? 90 : 90 - (minute - 60) / 6)) }
        let trend = try #require(history.currentTrend())
        #expect(trend.span == 3600)
        #expect(trend.percentPerHour == -10)
    }

    @Test func noTrendForAShortStretch() {
        var history = ChargeHistory()
        history.record(sample(0, charging: true))
        for minute in 1...10 { history.record(sample(Double(minute) * 60)) }
        #expect(history.currentTrend() == nil)
        #expect(ChargeHistory().currentTrend() == nil)
    }

    @Test func lastChargeSessionEndsAtUnplug() throws {
        var history = ChargeHistory()
        history.record(sample(0, 30, charging: true))
        history.record(sample(60, 35))  // brief pause, bridged
        history.record(sample(120, 40, charging: true))
        history.record(sample(3600, 70, charging: true))
        history.record(sample(3660, 70))
        history.record(sample(3720, 69))
        let session = try #require(history.lastChargeSession)
        #expect(session == ChargeSession(start: start, end: start.addingTimeInterval(3660),
                                         fromPercent: 30, toPercent: 70, isOngoing: false))
        #expect(session.duration == 3660)
    }

    @Test func ongoingChargeSession() throws {
        var history = ChargeHistory()
        history.record(sample(0, 50))
        history.record(sample(60, 51, charging: true))
        history.record(sample(120, 52, charging: true))
        let session = try #require(history.lastChargeSession)
        #expect(session.isOngoing)
        #expect(session.fromPercent == 51 && session.toPercent == 52)
    }

    @Test func noChargeSessionWhenNeverCharging() {
        var history = ChargeHistory()
        history.record(sample(0))
        history.record(sample(60))
        #expect(history.lastChargeSession == nil)
    }
}
