import Testing
@testable import SpannerCore

@Suite("Per-app energy")
struct AppEnergyTests {
    @Test func helpersCountTowardTheirOutermostApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppBundlePath.outermostApp(in: helper) == "/Applications/Google Chrome.app")
        #expect(AppBundlePath.outermostApp(in: "/usr/libexec/trustd") == nil)
        #expect(AppBundlePath.outermostApp(in: "/Applications/Notes.app") == "/Applications/Notes.app")
    }

    @Test func servicesOutsideAnAppCountTowardTheAppResponsibleForThem() {
        let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        #expect(AppBundlePath.owningApp(executable: webContent, responsible: "/Applications/Safari.app/Contents/MacOS/Safari")
            == "/Applications/Safari.app")
        // A process's own bundle wins over whoever launched it.
        #expect(AppBundlePath.owningApp(executable: "/Applications/Notes.app/Contents/MacOS/Notes",
                                        responsible: "/Applications/Terminal.app/Contents/MacOS/Terminal")
            == "/Applications/Notes.app")
        #expect(AppBundlePath.owningApp(executable: "/usr/libexec/corespeechd", responsible: "/usr/libexec/avconferenced") == nil)
        #expect(AppBundlePath.owningApp(executable: "/usr/sbin/cfprefsd", responsible: nil) == nil)
    }

    @Test func backgroundSumsProcessesOutsideAppsBusiestFirst() {
        let ranked = [
            AppPower(groupKey: "/Applications/Xcode.app", name: "Xcode", watts: 3, joules: 30),
            AppPower(groupKey: "/usr/libexec/corespeechd", name: "corespeechd", watts: 2, joules: 5),
            AppPower(groupKey: "pid:42", name: "PID 42", watts: 0.5, joules: 1),
        ]
        let background = BackgroundPower(ranked)
        #expect(background?.watts == 2.5)
        #expect(background?.joules == 6)
        #expect(background?.names == ["corespeechd", "PID 42"])
        #expect(ranked.filter(\.isApp).map(\.name) == ["Xcode"])
        #expect(BackgroundPower(Array(ranked.prefix(1))) == nil)
    }

    func sample(_ pid: Int32, _ nj: UInt64, _ key: String = "A") -> ProcessEnergySample {
        ProcessEnergySample(pid: pid, energyNanojoules: nj, groupKey: key, name: key)
    }

    @Test func firstSampleOnlySetsTheBaseline() {
        var accumulator = EnergyAccumulator()
        #expect(accumulator.update([sample(1, 5_000_000_000)], at: 0).isEmpty)
    }

    @Test func powerIsEnergyDeltaOverTimeSummedPerApp() {
        var accumulator = EnergyAccumulator()
        _ = accumulator.update([sample(1, 0), sample(2, 0), sample(3, 0, "B")], at: 0)
        let result = accumulator.update([sample(1, 2_000_000_000), sample(2, 2_000_000_000),
                                         sample(3, 1_000_000_000, "B")], at: 2)
        #expect(result.map(\.groupKey) == ["A", "B"])
        #expect(result[0].watts == 2) // 4 J over 2 s
        #expect(result[1].watts == 0.5)
        #expect(result[0].joules == 4)
    }

    @Test func totalsAccumulateAcrossIntervals() {
        var accumulator = EnergyAccumulator()
        _ = accumulator.update([sample(1, 0)], at: 0)
        _ = accumulator.update([sample(1, 1_000_000_000)], at: 1)
        let result = accumulator.update([sample(1, 3_000_000_000)], at: 2)
        #expect(result.first?.joules == 3)
        #expect(result.first?.watts == 2)
    }

    @Test func reusedPIDsAndNewProcessesAreSkipped() {
        var accumulator = EnergyAccumulator()
        _ = accumulator.update([sample(1, 9_000_000_000)], at: 0)
        // PID 1 restarted with a smaller counter; PID 2 is brand new.
        let result = accumulator.update([sample(1, 1_000), sample(2, 5_000_000_000)], at: 1)
        #expect(result.isEmpty)
    }

    @Test func clockGoingBackwardsYieldsNothing() {
        var accumulator = EnergyAccumulator()
        _ = accumulator.update([sample(1, 0)], at: 10)
        #expect(accumulator.update([sample(1, 1_000)], at: 5).isEmpty)
    }
}

@Suite("App volume")
struct AppVolumeTests {
    @Test func gainIsSquaredAndMuteSilences() {
        #expect(AppVolume(level: 0.5).gain == 0.25)
        #expect(AppVolume(level: 1).isUnity)
        #expect(AppVolume(level: 1, isMuted: true).gain == 0)
        #expect(!AppVolume(level: 1, isMuted: true).isUnity)
    }

    @Test func levelIsClamped() {
        #expect(AppVolume(level: 3).level == 1)
        #expect(AppVolume(level: -1).level == 0)
    }

    @Test func rampReachesTheTargetWithoutJumping() {
        var ramp = GainRamp(initial: 1, sampleRate: 1000, rampSeconds: 0.01) // 10 frames
        let first = ramp.next(toward: 0)
        #expect(first < 1 && first > 0.8)
        for _ in 0..<20 { _ = ramp.next(toward: 0) }
        #expect(ramp.current == 0)
    }
}
