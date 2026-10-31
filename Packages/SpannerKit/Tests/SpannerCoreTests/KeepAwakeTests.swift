import Foundation
import Testing
@testable import SpannerCore

@Suite("Keep awake session")
struct KeepAwakeTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func timedSessionEndsAfterItsDuration() {
        let session = KeepAwakeSession(duration: .minutes30, keepsDisplayOn: false, now: now)
        #expect(session.end == now.addingTimeInterval(1800))
        #expect(session.remaining(at: now.addingTimeInterval(600)) == 1200)
        #expect(!session.isExpired(at: now.addingTimeInterval(1799)))
        #expect(session.isExpired(at: now.addingTimeInterval(1800)))
    }

    @Test func remainingNeverGoesNegative() {
        let session = KeepAwakeSession(duration: .minutes15, keepsDisplayOn: true, now: now)
        #expect(session.remaining(at: now.addingTimeInterval(10_000)) == 0)
    }

    @Test func indefiniteSessionNeverExpires() {
        let session = KeepAwakeSession(duration: .indefinitely, keepsDisplayOn: false, now: now)
        #expect(session.end == nil)
        #expect(session.remaining(at: now.addingTimeInterval(1e9)) == nil)
        #expect(!session.isExpired(at: now.addingTimeInterval(1e9)))
        #expect(session.progress(at: now) == nil)
    }

    @Test func progressIsClampedToUnitRange() {
        let session = KeepAwakeSession(duration: .hour1, keepsDisplayOn: false, now: now)
        #expect(session.progress(at: now.addingTimeInterval(-50)) == 0)
        #expect(session.progress(at: now.addingTimeInterval(1800)) == 0.5)
        #expect(session.progress(at: now.addingTimeInterval(7200)) == 1)
    }

    @Test func everyFiniteDurationHasAPositiveInterval() {
        for duration in KeepAwakeDuration.allCases where duration != .indefinitely {
            #expect((duration.interval ?? 0) > 0, "\(duration)")
        }
    }
}

@Suite("Formatting")
struct FormattingTests {
    static let durationCases: [(seconds: Double, expected: String)] = [
        (0, "Less than a minute"),
        (59, "Less than a minute"),
        (60, "1 min"),
        (2700, "45 min"),
        (3600, "1 h"),
        (7500, "2 h 05 min"),
        (.infinity, "Less than a minute"),
    ]

    @Test(arguments: durationCases)
    func duration(_ testCase: (seconds: Double, expected: String)) {
        #expect(SpannerFormat.duration(testCase.seconds) == testCase.expected)
    }

    @Test func countdownShowsHoursOnlyWhenNeeded() {
        #expect(SpannerFormat.countdown(249) == "4:09")
        #expect(SpannerFormat.countdown(3849) == "1:04:09")
        #expect(SpannerFormat.countdown(-5) == "0:00")
        #expect(SpannerFormat.countdown(0.2) == "0:01")
    }
}
