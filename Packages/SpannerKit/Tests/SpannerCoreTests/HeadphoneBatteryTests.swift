import Foundation
import Testing
@testable import SpannerCore

struct HeadphoneBatteryTests {
    @Test func zeroLevelsAreUnknown() {
        let pods = HeadphoneBattery(id: "a", name: "AirPods Pro", left: 80, right: 0, chargingCase: 0)
        #expect(pods.left == 80)
        #expect(pods.right == nil)
        #expect(pods.chargingCase == nil)
        #expect(pods.hasBattery)
        #expect(!HeadphoneBattery(id: "b", name: "AirPods").hasBattery)
    }

    @Test func lowestIgnoresTheCase() {
        let pods = HeadphoneBattery(id: "a", name: "AirPods", left: 70, right: 45, chargingCase: 10)
        #expect(pods.lowest == 45)
        #expect(pods.level == .normal)
        let caseOnly = HeadphoneBattery(id: "a", name: "AirPods", chargingCase: 10)
        #expect(caseOnly.lowest == nil)
        #expect(caseOnly.level == nil)
    }

    @Test func summary() {
        #expect(HeadphoneBattery(id: "a", name: "AirPods", left: 80, right: 75, chargingCase: 40).summary
            == "L 80% · R 75% · Case 40%")
        #expect(HeadphoneBattery(id: "a", name: "AirPods", right: 75).summary == "R 75%")
        #expect(HeadphoneBattery(id: "a", name: "Beats Studio", single: 60).summary == "60%")
    }

    @Test func kindFromName() {
        #expect(HeadphoneBattery(id: "a", name: "Tiến’s AirPods Pro").kind == .airPodsPro)
        #expect(HeadphoneBattery(id: "a", name: "AirPods Max").kind == .airPodsMax)
        #expect(HeadphoneBattery(id: "a", name: "My AirPods").kind == .airPods)
        #expect(HeadphoneBattery(id: "a", name: "Beats Fit Pro").kind == .other)
    }
}

struct HeadphoneUsageDetectorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func pods(inEar: Bool?, left: Int = 80) -> HeadphoneBattery {
        HeadphoneBattery(id: "pods", name: "AirPods Pro", left: left, right: 80, chargingCase: 50, isInEar: inEar)
    }

    @Test func headphonesInUseAtLaunchDontTrigger() {
        var detector = HeadphoneUsageDetector()
        #expect(detector.update([pods(inEar: true)], now: start).isEmpty)
        #expect(detector.update([pods(inEar: true)], now: start + 5).isEmpty)
    }

    @Test func puttingThemInTriggersOnce() {
        var detector = HeadphoneUsageDetector()
        _ = detector.update([], now: start)
        #expect(detector.update([pods(inEar: false)], now: start + 1).isEmpty)
        #expect(detector.update([pods(inEar: true)], now: start + 2).map(\.id) == ["pods"])
        #expect(detector.update([pods(inEar: true)], now: start + 3).isEmpty)
    }

    @Test func connectingWithoutEarDetectionTriggers() {
        var detector = HeadphoneUsageDetector()
        _ = detector.update([], now: start)
        #expect(detector.update([pods(inEar: nil)], now: start + 1).map(\.id) == ["pods"])
    }

    @Test func waitsForTheFirstBatteryReport() {
        var detector = HeadphoneUsageDetector()
        _ = detector.update([], now: start)
        let unknown = HeadphoneBattery(id: "pods", name: "AirPods Pro", isInEar: true)
        #expect(detector.update([unknown], now: start + 1).isEmpty)
        #expect(detector.update([pods(inEar: true)], now: start + 2).map(\.id) == ["pods"])
    }

    @Test func briefRemovalDoesntRetrigger() {
        var detector = HeadphoneUsageDetector()
        _ = detector.update([], now: start)
        _ = detector.update([pods(inEar: true)], now: start + 1)
        _ = detector.update([pods(inEar: false)], now: start + 10)
        #expect(detector.update([pods(inEar: true)], now: start + 70).isEmpty)
        // A dropout (disconnect) is a stop too.
        _ = detector.update([], now: start + 80)
        #expect(detector.update([pods(inEar: true)], now: start + 90).isEmpty)
    }

    @Test func retriggersAfterTheRearmDelay() {
        var detector = HeadphoneUsageDetector()
        _ = detector.update([], now: start)
        _ = detector.update([pods(inEar: true)], now: start + 1)
        _ = detector.update([], now: start + 10)
        let later = start + 10 + HeadphoneUsageDetector.rearmDelay
        #expect(detector.update([pods(inEar: true)], now: later).map(\.id) == ["pods"])
    }

    @Test func tracksDevicesIndependently() {
        var detector = HeadphoneUsageDetector()
        let beats = HeadphoneBattery(id: "beats", name: "Beats Studio", single: 60)
        _ = detector.update([pods(inEar: true)], now: start)
        #expect(detector.update([pods(inEar: true), beats], now: start + 1).map(\.id) == ["beats"])
    }
}
