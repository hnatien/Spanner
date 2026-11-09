import Foundation
import Testing
@testable import SpannerCore

@Suite("System activity")
struct SystemActivityTests {
    // MARK: Rates

    @Test func ratesAreDeltasOverElapsedTime() throws {
        var meter = RateMeter()
        #expect(meter.update(["en0": ByteCounters(inbound: 1_000, outbound: 500)], at: 10) == nil)
        let ratesReading = meter.update(["en0": ByteCounters(inbound: 5_000, outbound: 900)], at: 12)
        let rates = try #require(ratesReading)
        #expect(rates == ByteRates(inbound: 2_000, outbound: 200))
    }

    @Test func ratesSumEverySource() throws {
        var meter = RateMeter()
        _ = meter.update(["en0": ByteCounters(inbound: 0, outbound: 0),
                          "en1": ByteCounters(inbound: 100, outbound: 100)], at: 0)
        let ratesReading = meter.update(["en0": ByteCounters(inbound: 300, outbound: 100),
                                               "en1": ByteCounters(inbound: 200, outbound: 300)], at: 2)
        let rates = try #require(ratesReading)
        #expect(rates == ByteRates(inbound: 200, outbound: 150))
    }

    @Test func counterResetBecomesTheNewBaselineInsteadOfASpike() throws {
        var meter = RateMeter()
        _ = meter.update(["en0": ByteCounters(inbound: 9_000_000, outbound: 4_000)], at: 0)
        // Interface went down and up: inbound restarted near zero.
        let resetReading = meter.update(["en0": ByteCounters(inbound: 100, outbound: 4_400)], at: 2)
        let reset = try #require(resetReading)
        #expect(reset == ByteRates(inbound: 0, outbound: 200))
        // The next tick measures from the restarted counter.
        let nextReading = meter.update(["en0": ByteCounters(inbound: 700, outbound: 4_400)], at: 4)
        let next = try #require(nextReading)
        #expect(next == ByteRates(inbound: 300, outbound: 0))
    }

    @Test func sourcesThatAppearOrDisappearDontSpike() throws {
        var meter = RateMeter()
        _ = meter.update(["en0": ByteCounters(inbound: 0, outbound: 0)], at: 0)
        // A drive with terabytes already counted attaches mid-session.
        let appearedReading = meter.update(["en0": ByteCounters(inbound: 10, outbound: 10),
                                                  "disk4": ByteCounters(inbound: 5_000_000_000_000, outbound: 1)],
                                                 at: 1)
        let appeared = try #require(appearedReading)
        #expect(appeared == ByteRates(inbound: 10, outbound: 10))
        let goneReading = meter.update([:], at: 2)
        let gone = try #require(goneReading)
        #expect(gone == ByteRates(inbound: 0, outbound: 0))
    }

    @Test func noRateWithoutElapsedTime() {
        var meter = RateMeter()
        _ = meter.update(["en0": ByteCounters(inbound: 0, outbound: 0)], at: 5)
        #expect(meter.update(["en0": ByteCounters(inbound: 100, outbound: 0)], at: 5) == nil)
        #expect(meter.update(["en0": ByteCounters(inbound: 200, outbound: 0)], at: 4) == nil)
    }

    @Test func resetForgetsTheBaseline() {
        var meter = RateMeter()
        _ = meter.update(["en0": ByteCounters(inbound: 0, outbound: 0)], at: 0)
        meter.reset()
        #expect(meter.update(["en0": ByteCounters(inbound: 1_000, outbound: 0)], at: 2) == nil)
    }

    @Test func totalsSumAndSaturate() {
        let total = ByteCounters.total([ByteCounters(inbound: 1, outbound: 2), ByteCounters(inbound: 3, outbound: 4)])
        #expect(total == ByteCounters(inbound: 4, outbound: 6))
        #expect(ByteCounters.total([]) == ByteCounters(inbound: 0, outbound: 0))
        let huge = ByteCounters.total([ByteCounters(inbound: .max, outbound: 1), ByteCounters(inbound: 1, outbound: 1)])
        #expect(huge == ByteCounters(inbound: .max, outbound: 2))
    }

    @Test func displayedRatesRoundToTheShownUnit() {
        let a = ByteRates(inbound: 1_234_567, outbound: 84_400).displayed
        let b = ByteRates(inbound: 1_190_000, outbound: 83_600).displayed
        #expect(a == b)
        #expect(ByteCounters(inbound: 245_107_195_904, outbound: 0).displayed.inbound == 245_000_000_000)
    }

    // MARK: Interfaces

    @Test func countsPhysicalActiveInterfacesOnly() {
        func counts(_ name: String, up: Bool = true, loopback: Bool = false, physical: Bool = true) -> Bool {
            NetworkInterfaceFilter.counts(name: name, isUp: up, isLoopback: loopback, isPhysicalType: physical)
        }
        #expect(counts("en0"))
        #expect(counts("en12"))
        #expect(!counts("en0", up: false))
        #expect(!counts("lo0", loopback: true))
        for virtual in ["utun0", "utun12", "awdl0", "llw0", "bridge0", "anpi1", "ap1", "nan0", "feth5449"] {
            #expect(!counts(virtual), "\(virtual) should be excluded")
        }
        #expect(!counts("gif0", physical: false))
        #expect(!counts(""))
        // A prefix only matches when the rest is the unit number.
        #expect(counts("apX0") == true)
    }

    // MARK: Volumes

    @Test func volumesFollowFindersSidebar() {
        #expect(VolumeUsage.isShown(path: "/", isLocal: true, isBrowsable: true))
        #expect(VolumeUsage.isShown(path: "/Volumes/Backup", isLocal: true, isBrowsable: true))
        #expect(!VolumeUsage.isShown(path: "/System/Volumes/Data", isLocal: true, isBrowsable: true))
        #expect(!VolumeUsage.isShown(path: "/System/Volumes/VM", isLocal: true, isBrowsable: false))
        #expect(!VolumeUsage.isShown(path: "/Volumes/Recovery", isLocal: true, isBrowsable: false))
        #expect(!VolumeUsage.isShown(path: "/Volumes/Share", isLocal: false, isBrowsable: true))
    }

    @Test func volumeUsageNeverUnderflows() {
        let volume = VolumeUsage(id: "a", name: "Disk", isStartup: false, isInternal: false, total: 100, available: 150)
        #expect(volume.used == 0)
        #expect(volume.fraction == 0)
        let empty = VolumeUsage(id: "b", name: "Empty", isStartup: false, isInternal: false, total: 0, available: 0)
        #expect(empty.fraction == 0)
        let half = VolumeUsage(id: "c", name: "Half", isStartup: true, isInternal: true, total: 200, available: 100)
        #expect(half.used == 100)
        #expect(half.fraction == 0.5)
    }

    @Test func volumesThatLookTheSameCompareEqual() {
        let a = VolumeUsage(id: "a", name: "HD", isStartup: true, isInternal: true,
                            total: 245_107_195_904, available: 19_739_409_938).displayed
        let b = VolumeUsage(id: "a", name: "HD", isStartup: true, isInternal: true,
                            total: 245_107_195_904, available: 19_741_000_000).displayed
        #expect(a == b)
        #expect(a.available == 20_000_000_000)   // shown as "20 GB"
    }

    @Test func startupVolumeComesFirst() {
        func volume(_ name: String, startup: Bool = false) -> VolumeUsage {
            VolumeUsage(id: name, name: name, isStartup: startup, isInternal: startup, total: 1, available: 0)
        }
        let ordered = VolumeUsage.ordered([volume("Zip"), volume("Macintosh HD", startup: true), volume("Archive")])
        #expect(ordered.map(\.name) == ["Macintosh HD", "Archive", "Zip"])
    }

    // MARK: Load average

    @Test func loadAverageRoundsAndRejectsBadReadings() throws {
        let load = try #require(LoadAverage([1.8249, 2.0, 2.105]))
        #expect(load.one == 1.82)
        #expect(load.formatted == "1.82 · 2.00 · 2.11")
        #expect(LoadAverage([1, 2]) == nil)
        #expect(LoadAverage([.nan, 1, 1]) == nil)
        #expect(LoadAverage([-1, 1, 1]) == nil)
    }

    // MARK: Processes

    private func sample(_ pid: Int32, start: UInt64 = 1, cpu: UInt64, memory: UInt64 = 0,
                        group: String? = nil, name: String? = nil) -> ProcessSample {
        ProcessSample(pid: pid, startTime: start, cpuTime: cpu, footprint: memory,
                      groupKey: group ?? "/bin/p\(pid)", name: name ?? "p\(pid)")
    }

    @Test func cpuNeedsTwoSamplesButMemoryShowsAtOnce() {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        let first = tracker.update([sample(1, cpu: 0, memory: 1_048_576)], at: 0, limit: 5)
        #expect(first.byCPU == nil)
        #expect(first.byMemory.map(\.name) == ["p1"])
        #expect(first.byMemory.first?.memory == 1_048_576)
    }

    @Test func cpuUsesTheMachTimebase() throws {
        // Apple silicon: 125/3 ns per tick. 24 million ticks = 1 s of CPU.
        var tracker = ProcessTracker(timebaseNumer: 125, timebaseDenom: 3)
        _ = tracker.update([sample(1, cpu: 0)], at: 0, limit: 5)
        let ranking = tracker.update([sample(1, cpu: 48_000_000)], at: 4, limit: 5)
        let top = try #require(ranking.byCPU?.first)
        #expect(top.cpu == 0.5)
    }

    @Test func cpuAddsUpAcrossAnAppsProcesses() throws {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        let app = "/Applications/Safari.app"
        _ = tracker.update([sample(1, cpu: 0, memory: 100, group: app, name: "Safari"),
                            sample(2, cpu: 0, memory: 200, group: app, name: "Safari")], at: 0, limit: 5)
        let ranking = tracker.update([sample(1, cpu: 1_000_000_000, memory: 100, group: app, name: "Safari"),
                                      sample(2, cpu: 2_000_000_000, memory: 200, group: app, name: "Safari")],
                                     at: 2, limit: 5)
        let safari = try #require(ranking.byCPU?.first)
        #expect(safari.cpu == 1.5)
        #expect(safari.isApp)
        #expect(ranking.byCPU?.count == 1)
    }

    @Test func reusedPidStartsFresh() throws {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        _ = tracker.update([sample(7, start: 100, cpu: 5_000_000_000)], at: 0, limit: 5)
        // pid 7 exited and a new process took it: its time is not a delta.
        let ranking = tracker.update([sample(7, start: 200, cpu: 9_000_000_000)], at: 2, limit: 5)
        #expect(try #require(ranking.byCPU?.first).cpu == 0)
    }

    @Test func exitedAndNewProcessesDontSkewCPU() throws {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        _ = tracker.update([sample(1, cpu: 0), sample(2, cpu: 0)], at: 0, limit: 5)
        let ranking = tracker.update([sample(1, cpu: 200_000_000), sample(3, cpu: 50_000_000_000)], at: 1, limit: 5)
        let byCPU = try #require(ranking.byCPU)
        #expect(byCPU.map(\.name) == ["p1", "p3"])
        #expect(byCPU.map(\.cpu) == [0.2, 0])
    }

    @Test func rankingBreaksTiesByNameAndHonoursTheLimit() throws {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        let pids: [Int32] = [1, 2, 3, 4]
        _ = tracker.update(pids.map { sample($0, cpu: 0) }, at: 0, limit: 3)
        let ranking = tracker.update([sample(1, cpu: 100_000_000, name: "delta"),
                                      sample(2, cpu: 100_000_000, name: "alpha"),
                                      sample(3, cpu: 900_000_000, name: "charlie"),
                                      sample(4, cpu: 0, name: "bravo")], at: 1, limit: 3)
        #expect(try #require(ranking.byCPU).map(\.name) == ["charlie", "alpha", "delta"])
    }

    @Test func fewerProcessesThanTheLimitAreAllShown() {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        let ranking = tracker.update([sample(1, cpu: 0, memory: 3_000_000), sample(2, cpu: 0, memory: 9_000_000)],
                                     at: 0, limit: 8)
        #expect(ranking.byMemory.map(\.name) == ["p2", "p1"])
        #expect(tracker.update([], at: 1, limit: 8) == ProcessRanking(byCPU: [], byMemory: []))
    }

    @Test func noCPUWithoutElapsedTime() {
        var tracker = ProcessTracker(timebaseNumer: 1, timebaseDenom: 1)
        _ = tracker.update([sample(1, cpu: 0)], at: 3, limit: 5)
        #expect(tracker.update([sample(1, cpu: 1_000)], at: 3, limit: 5).byCPU == nil)
    }
}
