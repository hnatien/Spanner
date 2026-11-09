import Foundation
import Testing
@testable import SpannerCore

@Suite("System stats")
struct SystemStatsTests {
    @Test func cpuLoadIsBusyTicksOverAllTicks() throws {
        let earlier = [CoreTicks(user: 100, system: 50, idle: 850, nice: 0),
                       CoreTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let later = [CoreTicks(user: 160, system: 70, idle: 870, nice: 0),   // 80 busy of 100
                     CoreTicks(user: 10, system: 0, idle: 1090, nice: 0)]   // 10 busy of 100
        let load = try #require(CPULoad(from: earlier, to: later))
        #expect(load.total == 0.45)
        #expect(load.cores == [0.8, 0.1])
    }

    @Test func cpuLoadSplitsUserAndSystemTime() throws {
        let earlier = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0),
                       CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let later = [CoreTicks(user: 50, system: 20, idle: 20, nice: 10),   // 60 user, 20 system of 100
                     CoreTicks(user: 0, system: 40, idle: 60, nice: 0)]     // 40 system of 100
        let load = try #require(CPULoad(from: earlier, to: later))
        #expect(load.user == 0.3)
        #expect(load.system == 0.3)
        #expect(load.total == load.user + load.system)
        #expect(load.cores == [0.8, 0.4])
    }

    @Test func idleCoresHaveNoUserOrSystemTime() throws {
        let earlier = [CoreTicks(user: 5, system: 5, idle: 0, nice: 5)]
        let later = [CoreTicks(user: 5, system: 5, idle: 100, nice: 5)]
        let load = try #require(CPULoad(from: earlier, to: later))
        #expect(load.user == 0)
        #expect(load.system == 0)
        #expect(load.total == 0)
    }

    @Test func cpuTicksThatWrapStillGiveTheRightLoad() throws {
        let earlier = [CoreTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 9, nice: 0)]
        let later = [CoreTicks(user: 10, system: 0, idle: 10, nice: 0)]
        let load = try #require(CPULoad(from: earlier, to: later))
        #expect(load.total == 0.5)
    }

    @Test func cpuLoadNeedsMatchingReadingsAndElapsedTime() {
        let ticks = [CoreTicks(user: 1, system: 1, idle: 1, nice: 1)]
        #expect(CPULoad(from: [], to: []) == nil)
        #expect(CPULoad(from: ticks, to: ticks + ticks) == nil)
        #expect(CPULoad(from: ticks, to: ticks) == nil)
    }

    @Test func memoryUsedMatchesActivityMonitor() {
        let memory = MemoryUsage(pageSize: 16_384, total: 16 * 1_073_741_824,
                                 internalPages: 300_000, purgeablePages: 20_000, wiredPages: 100_000,
                                 compressorPages: 50_000, externalPages: 80_000,
                                 swapUsed: 0, pressure: .normal)
        #expect(memory.app == 280_000 * 16_384)
        #expect(memory.cached == 100_000 * 16_384)
        #expect(memory.used == 430_000 * 16_384)
        #expect(abs(memory.fraction - 430_000.0 * 16_384 / (16 * 1_073_741_824)) < 1e-12)
    }

    @Test func memoryNeverExceedsPhysicalOrUnderflows() {
        let memory = MemoryUsage(pageSize: 1, total: 100, internalPages: 5, purgeablePages: 10,
                                 wiredPages: 200, compressorPages: 0, externalPages: 0,
                                 swapUsed: 0, pressure: .normal)
        #expect(memory.app == 0)
        #expect(memory.used == 100)
        #expect(memory.fraction == 1)
        #expect(MemoryUsage(total: 0, app: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
            .fraction == 0)
    }

    @Test func memoryThatLooksTheSameIsNotRepublished() {
        let gigabyte: UInt64 = 1_073_741_824
        let a = MemoryUsage(total: 16 * gigabyte, app: 5 * gigabyte, wired: 2 * gigabyte, compressed: gigabyte,
                            cached: 3 * gigabyte, swapUsed: 0, pressure: .normal)
        var b = a
        b.app += 4_096 * 3   // a few pages: still "5.0 GB"
        #expect(MemoryUsage.displaysSame(a, b))
        b.app += gigabyte / 5   // "5.2 GB"
        #expect(!MemoryUsage.displaysSame(a, b))
        var pressured = a
        pressured.pressure = .warning
        #expect(!MemoryUsage.displaysSame(a, pressured))
        #expect(MemoryUsage.displaysSame(nil, nil))
        #expect(!MemoryUsage.displaysSame(a, nil))
        #expect(!MemoryUsage.displaysSame(nil, a))
    }

    @Test func pressureLevelsMapFromTheKernel() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
        #expect(MemoryPressure(level: 0) == .normal)
    }

    @Test func gpuReadsUtilizationAndRejectsMissingKeys() throws {
        let gpu = try #require(GPUUsage(performanceStatistics: ["Device Utilization %": NSNumber(value: 30),
                                                                "In use system memory": NSNumber(value: 1024)]))
        #expect(gpu.utilization == 0.3)
        #expect(gpu.memoryInUse == 1024)
        #expect(GPUUsage(performanceStatistics: ["Renderer Utilization %": NSNumber(value: 30)]) == nil)
        #expect(GPUUsage(performanceStatistics: ["Device Utilization %": NSNumber(value: 140)])?.utilization == 1)
    }

    @Test func snapshotsThatLookTheSameCompareEqual() {
        let a = SystemSnapshot(cpu: CPULoad(total: 0.4149, user: 0.3049, system: 0.11, cores: [0.201]), memory: nil,
                               gpu: GPUUsage(utilization: 0.3, memoryInUse: nil))
        let b = SystemSnapshot(cpu: CPULoad(total: 0.4101, user: 0.2951, system: 0.1149, cores: [0.199]), memory: nil,
                               gpu: GPUUsage(utilization: 0.3001, memoryInUse: nil))
        #expect(a == b)
        #expect(a.cpu?.total == 0.41)
        #expect(a.cpu?.user == 0.3)
    }

    @Test func coreKindsMapClusterLettersAndKeepUnknownOnes() {
        #expect(CoreKind(clusterType: "P") == .performance)
        #expect(CoreKind(clusterType: "E") == .efficiency)
        #expect(CoreKind(clusterType: "S") == .other("S"))
        #expect(CoreKind.other("S").title == "S cores")
    }

    @Test func coreClustersFollowKernelOrder() {
        let kinds: [CoreKind] = [.efficiency, .efficiency, .other("S"), .performance, .performance, .performance]
        let clusters = CoreKind.clusters(kinds)
        #expect(clusters.map(\.kind) == [.efficiency, .other("S"), .performance])
        #expect(clusters.map(\.range) == [0..<2, 2..<3, 3..<6])
        #expect(CoreKind.clusters([]).isEmpty)
        #expect(CoreKind.clusters([.performance]).map(\.range) == [0..<1])
    }

    @Test func coreSummaryNamesEveryClusterType() {
        let m4: [CoreKind] = Array(repeating: .efficiency, count: 6) + Array(repeating: .performance, count: 4)
        #expect(CoreKind.summary(m4) == "4 Performance · 6 Efficiency cores")
        let threeTier: [CoreKind] = [.efficiency, .efficiency, .other("S"), .performance]
        #expect(CoreKind.summary(threeTier) == "1 Performance · 2 Efficiency · 1 S cores")
        #expect(CoreKind.summary([.other("S"), .other("S")]) == "2 S cores")
        #expect(CoreKind.summary([]) == nil)
    }

    @Test func historyKeepsTheNewestValues() {
        var history = MetricHistory(capacity: 3)
        for value in [0.1, 0.2, 0.3, 0.4] { history.append(value) }
        #expect(history.values == [0.2, 0.3, 0.4])
        history.removeAll()
        #expect(history.values.isEmpty)
        #expect(history.last == nil)
    }

    @Test func historyWrapsAroundOldestFirst() {
        var history = MetricHistory(capacity: 4)
        for value in 1...10 { history.append(Double(value)) }
        #expect(history.values == [7, 8, 9, 10])
        #expect(history.count == 4)
        #expect(history.last == 10)
        // Ids are positions in the whole sequence, so each sample keeps its
        // id as the buffer wraps and charts don't re-diff every point.
        #expect(history.samples.map(\.id) == [6, 7, 8, 9])
        #expect(history.idDomain == 6...9)
        history.append(11)
        #expect(history.samples.map(\.id) == [7, 8, 9, 10])
    }

    @Test func historyWithCapacityOneKeepsOnlyTheLatest() {
        var history = MetricHistory(capacity: 1)
        #expect(history.values.isEmpty)
        history.append(0.5)
        history.append(0.7)
        #expect(history.values == [0.7])
        #expect(history.last == 0.7)
        #expect(history.samples == [MetricHistory.Sample(id: 1, value: 0.7)])
    }

    @Test func historyIdsKeepCountingAfterReset() {
        var history = MetricHistory(capacity: 3)
        history.append(1)
        history.append(2)
        history.removeAll()
        history.append(3)
        #expect(history.samples == [MetricHistory.Sample(id: 2, value: 3)])
        #expect(history.idDomain == 0...2)
    }

    @Test func historiesWithTheSameValuesCompareEqual() {
        var wrapped = MetricHistory(capacity: 2)
        for value in [1.0, 2, 3] { wrapped.append(value) }
        var other = MetricHistory(capacity: 2)
        for value in [9.0, 2, 3] { other.append(value) }
        #expect(wrapped == other)
        other.append(4)
        #expect(wrapped != other)
    }

    @Test func formatsMemoryAndPercent() {
        #expect(SpannerFormat.memory(8_912_896_000) == "8.3 GB")
        #expect(SpannerFormat.memory(536_870_912) == "512 MB")
        #expect(SpannerFormat.percent(0.416) == "42%")
        #expect(SpannerFormat.percent(1.4) == "100%")
        #expect(SpannerFormat.displayedMemory(8_912_896_000) == SpannerFormat.displayedMemory(8_900_000_000))
        #expect(SpannerFormat.displayedMemory(536_870_912 + 100) == 536_870_912)
    }

    @Test func formatsBytesInDecimalUnits() {
        #expect(SpannerFormat.bytes(0) == "0 B")
        #expect(SpannerFormat.bytes(999) == "999 B")
        #expect(SpannerFormat.bytes(1_000) == "1.0 KB")
        #expect(SpannerFormat.bytes(1_234_567) == "1.2 MB")
        #expect(SpannerFormat.bytes(84_400) == "84 KB")
        #expect(SpannerFormat.bytes(245_107_195_904) == "245 GB")
        // Rounding up to 1000 moves to the next unit instead of "1000 KB".
        #expect(SpannerFormat.bytes(999_700) == "1.0 MB")
        // 9.96 rounds to 10, which shows without a decimal.
        #expect(SpannerFormat.bytes(9_960) == "10 KB")
        #expect(SpannerFormat.bytes(UInt64.max) == "18447 PB")
    }

    @Test func formatsRatesAndTheirDisplayedValue() {
        #expect(SpannerFormat.rate(0) == "0 B/s")
        #expect(SpannerFormat.rate(1_250_000) == "1.3 MB/s")
        #expect(SpannerFormat.rate(-5) == "0 B/s")
        #expect(SpannerFormat.rate(.nan) == "0 B/s")
        #expect(SpannerFormat.rate(.infinity) == "0 B/s")
        #expect(SpannerFormat.displayedBytes(1_234_567) == 1_200_000)
        #expect(SpannerFormat.displayedBytes(84_400) == 84_000)
        #expect(SpannerFormat.displayedBytes(512.4) == 512)
    }

    @Test func formatsProcessCPUPastOneCore() {
        #expect(SpannerFormat.processCPU(0.123) == "12.3%")
        #expect(SpannerFormat.processCPU(2.4) == "240.0%")
        #expect(SpannerFormat.processCPU(0) == "0.0%")
        #expect(SpannerFormat.processCPU(-1) == "0.0%")
        #expect(SpannerFormat.processCPU(.nan) == "0.0%")
    }

    @Test func formatsUptime() {
        #expect(SpannerFormat.uptime(30) == "Less than a minute")
        #expect(SpannerFormat.uptime(12 * 60) == "12 min")
        #expect(SpannerFormat.uptime(2 * 3600 + 5 * 60) == "2 h 05 min")
        #expect(SpannerFormat.uptime(86_400) == "1 d")
        #expect(SpannerFormat.uptime(7 * 86_400 + 4 * 3600 + 59 * 60) == "7 d 4 h")
        #expect(SpannerFormat.uptime(.nan) == "Less than a minute")
    }
}
