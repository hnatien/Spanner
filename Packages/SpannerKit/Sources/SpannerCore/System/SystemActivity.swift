import Foundation

// MARK: - Byte counters and rates

/// Cumulative byte counters for one source: bytes received and sent by a
/// network interface, or read and written by a drive.
public struct ByteCounters: Equatable, Sendable {
    /// Received, or read.
    public var inbound: UInt64
    /// Sent, or written.
    public var outbound: UInt64

    public init(inbound: UInt64, outbound: UInt64) {
        self.inbound = inbound
        self.outbound = outbound
    }

    /// Sum over every source. The kernel's counters are 64-bit, so the sum
    /// only overflows after exabytes; it saturates rather than trapping.
    public static func total(_ counters: some Sequence<ByteCounters>) -> ByteCounters {
        counters.reduce(ByteCounters(inbound: 0, outbound: 0)) { sum, next in
            let inbound = sum.inbound.addingReportingOverflow(next.inbound)
            let outbound = sum.outbound.addingReportingOverflow(next.outbound)
            return ByteCounters(inbound: inbound.overflow ? .max : inbound.partialValue,
                                outbound: outbound.overflow ? .max : outbound.partialValue)
        }
    }

    /// Rounded to what `SpannerFormat.bytes` shows.
    public var displayed: ByteCounters {
        ByteCounters(inbound: UInt64(SpannerFormat.displayedBytes(Double(inbound))),
                     outbound: UInt64(SpannerFormat.displayedBytes(Double(outbound))))
    }
}

/// Bytes per second in each direction.
public struct ByteRates: Equatable, Sendable {
    public var inbound: Double
    public var outbound: Double

    public init(inbound: Double, outbound: Double) {
        self.inbound = inbound
        self.outbound = outbound
    }

    /// Rounded to what `SpannerFormat.rate` shows, so a reading that looks
    /// the same compares equal and doesn't redraw.
    public var displayed: ByteRates {
        ByteRates(inbound: SpannerFormat.displayedBytes(inbound), outbound: SpannerFormat.displayedBytes(outbound))
    }
}

/// Turns cumulative per-source counters into rates.
///
/// Counters restart when an interface goes down and up, a drive is
/// re-attached or the Mac wakes, and a new source can reuse an old name. A
/// counter that went backwards therefore becomes the new baseline and adds
/// nothing, rather than reading as a huge spike; a new source counts from
/// its second reading.
public struct RateMeter: Sendable {
    private var previous: [String: ByteCounters] = [:]
    private var lastTime: TimeInterval?

    public init() {}

    /// Forgets the baseline, so the next rate isn't averaged over a pause.
    public mutating func reset() {
        previous = [:]
        lastTime = nil
    }

    /// Rates since the previous update, keyed by source; nil on the first
    /// update and when no time passed. `time` is monotonic seconds.
    public mutating func update(_ counters: [String: ByteCounters], at time: TimeInterval) -> ByteRates? {
        defer {
            previous = counters
            lastTime = time
        }
        guard let lastTime, time > lastTime else { return nil }
        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        for (source, now) in counters {
            guard let before = previous[source] else { continue }
            if now.inbound >= before.inbound { inbound += now.inbound - before.inbound }
            if now.outbound >= before.outbound { outbound += now.outbound - before.outbound }
        }
        let elapsed = time - lastTime
        return ByteRates(inbound: Double(inbound) / elapsed, outbound: Double(outbound) / elapsed)
    }
}

// MARK: - Network interfaces

/// Which interfaces count toward network throughput.
public enum NetworkInterfaceFilter {
    /// Virtual interfaces whose traffic also crosses a physical one (VPN
    /// tunnels, AirDrop and Sidecar links, bridges, the Apple Silicon debug
    /// link, hotspot and feth pairs), so counting them would double it.
    static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "anpi", "ap", "nan", "feth",
                                   "vmenet", "gif", "stf", "ipsec", "ppp"]

    /// True for an interface that is up and running, isn't loopback, is a
    /// physical link type (Ethernet, Wi-Fi, cellular) and isn't one of the
    /// virtual families above. Prefixes match only when followed by the
    /// unit number, so "en0" never matches "e…" rules by accident.
    public static func counts(name: String, isUp: Bool, isLoopback: Bool, isPhysicalType: Bool) -> Bool {
        guard isUp, !isLoopback, isPhysicalType, !name.isEmpty else { return false }
        return !excludedPrefixes.contains { prefix in
            name.hasPrefix(prefix) && name.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
    }
}

/// The interface carrying the default route, for the Network card's label.
public struct NetworkInterfaceInfo: Equatable, Sendable {
    /// BSD name, "en0".
    public let name: String
    /// What System Settings calls it: "Wi-Fi", "Ethernet".
    public let displayName: String?
    public let ipv4: String?

    public init(name: String, displayName: String?, ipv4: String?) {
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
    }
}

// MARK: - Volumes

/// Capacity of one mounted volume.
public struct VolumeUsage: Identifiable, Equatable, Sendable {
    /// Volume UUID, or the mount path when there is none.
    public let id: String
    public let name: String
    public let isStartup: Bool
    public let isInternal: Bool
    public let total: UInt64
    /// What Finder shows as available: free space plus purgeable space
    /// macOS will clear for important work.
    public let available: UInt64

    public init(id: String, name: String, isStartup: Bool, isInternal: Bool, total: UInt64, available: UInt64) {
        self.id = id
        self.name = name
        self.isStartup = isStartup
        self.isInternal = isInternal
        self.total = total
        self.available = min(available, total)
    }

    public var used: UInt64 { total - available }

    /// 0...1 of the volume in use.
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Sizes rounded to what `SpannerFormat.bytes` shows, so free space
    /// that changes by a few bytes doesn't redraw the list.
    public var displayed: VolumeUsage {
        VolumeUsage(id: id, name: name, isStartup: isStartup, isInternal: isInternal,
                    total: UInt64(SpannerFormat.displayedBytes(Double(total))),
                    available: UInt64(SpannerFormat.displayedBytes(Double(available))))
    }

    /// Finder's sidebar rule: local, browsable volumes, without the system
    /// and snapshot volumes macOS mounts under /System/Volumes.
    public static func isShown(path: String, isLocal: Bool, isBrowsable: Bool) -> Bool {
        isLocal && isBrowsable && path != "/System/Volumes" && !path.hasPrefix("/System/Volumes/")
    }

    /// Startup volume first, then by name.
    public static func ordered(_ volumes: [VolumeUsage]) -> [VolumeUsage] {
        volumes.sorted {
            $0.isStartup != $1.isStartup ? $0.isStartup
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Load average

/// Average number of runnable threads over 1, 5 and 15 minutes, rounded to
/// the two decimals shown.
public struct LoadAverage: Equatable, Sendable {
    public let one: Double
    public let five: Double
    public let fifteen: Double

    /// Nil unless all three values are present and finite.
    public init?(_ values: [Double]) {
        guard values.count >= 3, values.prefix(3).allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        one = Self.round(values[0])
        five = Self.round(values[1])
        fifteen = Self.round(values[2])
    }

    /// "1.82 · 2.01 · 2.10"
    public var formatted: String {
        [one, five, fifteen].map { String(format: "%.2f", $0) }.joined(separator: " · ")
    }

    private static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

// MARK: - Processes

/// One process's counters at a moment, from `proc_pid_rusage`.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    /// `ri_proc_start_abstime`: tells a reused pid from the process it replaced.
    public let startTime: UInt64
    /// `ri_user_time + ri_system_time`, in mach absolute time units.
    public let cpuTime: UInt64
    /// `ri_phys_footprint`: Activity Monitor's "Memory" column.
    public let footprint: UInt64
    /// What to group by: the owning app bundle path, or the executable path.
    public let groupKey: String
    public let name: String

    public init(pid: Int32, startTime: UInt64, cpuTime: UInt64, footprint: UInt64, groupKey: String, name: String) {
        self.pid = pid
        self.startTime = startTime
        self.cpuTime = cpuTime
        self.footprint = footprint
        self.groupKey = groupKey
        self.name = name
    }
}

/// CPU and memory of one app (all its processes) or one standalone process.
public struct ProcessUsage: Identifiable, Equatable, Sendable {
    public var id: String { groupKey }
    public let groupKey: String
    public let name: String
    /// Over the last interval, as a fraction of one core (1 = 100%, as in
    /// Activity Monitor; above 1 with several busy threads), rounded to the
    /// 0.1% shown.
    public let cpu: Double
    /// Footprint, rounded to what `SpannerFormat.memory` shows.
    public let memory: UInt64

    public init(groupKey: String, name: String, cpu: Double, memory: UInt64) {
        self.groupKey = groupKey
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }

    /// False for processes outside any app bundle, grouped by their own path.
    public var isApp: Bool { groupKey.hasSuffix(".app") }
}

/// The busiest apps by CPU and by memory.
public struct ProcessRanking: Equatable, Sendable {
    /// Nil until two samples exist, since CPU is a difference.
    public let byCPU: [ProcessUsage]?
    public let byMemory: [ProcessUsage]

    public init(byCPU: [ProcessUsage]?, byMemory: [ProcessUsage]) {
        self.byCPU = byCPU
        self.byMemory = byMemory
    }
}

/// Turns successive process samples into per-app CPU and memory rankings.
///
/// CPU time is cumulative per process, so load is the difference between
/// two samples over the time between them. Processes are matched on pid
/// plus start time, so a reused pid starts fresh instead of inheriting (or
/// subtracting) another process's time.
public struct ProcessTracker: Sendable {
    private struct Key: Hashable {
        let pid: Int32
        let startTime: UInt64
    }

    /// Nanoseconds per mach time unit. 1 on Intel, 125/3 on Apple silicon:
    /// treating mach units as nanoseconds there undercounts CPU 40-fold.
    private let nanosecondsPerTick: Double
    private var previous: [Key: UInt64] = [:]
    private var lastTime: TimeInterval?

    /// `numer` and `denom` from `mach_timebase_info`.
    public init(timebaseNumer: UInt32, timebaseDenom: UInt32) {
        nanosecondsPerTick = timebaseDenom > 0 ? Double(timebaseNumer) / Double(timebaseDenom) : 1
    }

    /// Forgets the baseline, so the next CPU figures aren't averaged over a pause.
    public mutating func reset() {
        previous = [:]
        lastTime = nil
    }

    /// The top `limit` groups by CPU and by memory. `time` is monotonic seconds.
    public mutating func update(_ samples: [ProcessSample], at time: TimeInterval, limit: Int) -> ProcessRanking {
        var cpuTicks: [String: UInt64] = [:]
        var memory: [String: UInt64] = [:]
        var names: [String: String] = [:]
        var current: [Key: UInt64] = [:]
        current.reserveCapacity(samples.count)
        for sample in samples {
            let key = Key(pid: sample.pid, startTime: sample.startTime)
            current[key] = sample.cpuTime
            names[sample.groupKey] = names[sample.groupKey] ?? sample.name
            memory[sample.groupKey, default: 0] += sample.footprint
            if let before = previous[key], sample.cpuTime >= before {
                cpuTicks[sample.groupKey, default: 0] += sample.cpuTime - before
            }
        }
        let elapsed = lastTime.map { time - $0 } ?? 0
        let hasCPU = lastTime != nil && elapsed > 0
        previous = current
        lastTime = time

        let groups = memory.map { key, bytes in
            let seconds = Double(cpuTicks[key] ?? 0) * nanosecondsPerTick / 1e9
            return ProcessUsage(groupKey: key, name: names[key] ?? key,
                                cpu: hasCPU ? (seconds / elapsed * 1000).rounded() / 1000 : 0,
                                memory: SpannerFormat.displayedMemory(bytes))
        }
        let byCPU = hasCPU ? Self.top(groups, limit: limit, by: \.cpu) : nil
        return ProcessRanking(byCPU: byCPU, byMemory: Self.top(groups, limit: limit, by: \.memory))
    }

    /// Highest first; ties by name, then key, so equal values keep a
    /// stable order between samples instead of swapping rows.
    private static func top<Value: Comparable>(_ groups: [ProcessUsage], limit: Int,
                                               by value: (ProcessUsage) -> Value) -> [ProcessUsage] {
        let ranked = groups.sorted {
            let a = value($0), b = value($1)
            if a != b { return a > b }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.groupKey < $1.groupKey
        }
        return Array(ranked.prefix(max(0, limit)))
    }
}
