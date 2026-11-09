import Foundation

/// Cumulative scheduler ticks for one logical core, as the kernel reports
/// them (`PROCESSOR_CPU_LOAD_INFO`). The counters are 32-bit and wrap, so
/// differences use wrapping subtraction.
public struct CoreTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// User, system and total ticks elapsed since `earlier`. Nice ticks
    /// (user code at lowered priority) count as user, as in Activity Monitor.
    func delta(since earlier: CoreTicks) -> (user: UInt64, system: UInt64, total: UInt64) {
        let user = UInt64(user &- earlier.user) + UInt64(nice &- earlier.nice)
        let system = UInt64(system &- earlier.system)
        let idle = UInt64(idle &- earlier.idle)
        return (user, system, user + system + idle)
    }
}

/// CPU load between two tick readings.
public struct CPULoad: Equatable, Sendable {
    /// 0...1 across every core.
    public var total: Double
    /// 0...1 across every core spent in apps' own code (including nice).
    public var user: Double
    /// 0...1 across every core spent in the kernel on apps' behalf.
    public var system: Double
    /// 0...1 per logical core, in kernel order.
    public var cores: [Double]

    public init(total: Double, user: Double, system: Double, cores: [Double]) {
        self.total = total
        self.user = user
        self.system = system
        self.cores = cores
    }

    /// Load from `earlier` to `later`; nil when the readings don't describe
    /// the same cores or no time passed.
    public init?(from earlier: [CoreTicks], to later: [CoreTicks]) {
        guard !earlier.isEmpty, earlier.count == later.count else { return nil }
        var userSum: UInt64 = 0
        var systemSum: UInt64 = 0
        var totalSum: UInt64 = 0
        var cores: [Double] = []
        cores.reserveCapacity(later.count)
        for (old, new) in zip(earlier, later) {
            let delta = new.delta(since: old)
            userSum += delta.user
            systemSum += delta.system
            totalSum += delta.total
            cores.append(delta.total > 0 ? Double(delta.user + delta.system) / Double(delta.total) : 0)
        }
        guard totalSum > 0 else { return nil }
        let total = Double(totalSum)
        self.init(total: Double(userSum + systemSum) / total, user: Double(userSum) / total,
                  system: Double(systemSum) / total, cores: cores)
    }
}

/// Kind of a logical core on Apple silicon, from the device tree's
/// one-letter `cluster-type`.
public enum CoreKind: Hashable, Sendable {
    case performance, efficiency
    /// A cluster type this version doesn't name yet (M5 and later add
    /// "super" cores), kept as its letter so its cores still form their own
    /// labelled group instead of hiding every label.
    case other(String)

    public init(clusterType: String) {
        switch clusterType {
        case "P": self = .performance
        case "E": self = .efficiency
        default: self = .other(clusterType)
        }
    }

    /// Label under a cluster's bars.
    public var title: String {
        switch self {
        case .performance: "Performance"
        case .efficiency: "Efficiency"
        case .other(let letter): "\(letter) cores"
        }
    }

    private var shortTitle: String {
        switch self {
        case .other(let letter): letter
        default: title
        }
    }

    /// Consecutive runs of one kind, in kernel order: each becomes a group
    /// of bars.
    public static func clusters(_ kinds: [CoreKind]) -> [CoreCluster] {
        var clusters: [CoreCluster] = []
        var start = 0
        for index in kinds.indices.dropFirst() where kinds[index] != kinds[start] {
            clusters.append(CoreCluster(kind: kinds[start], range: start..<index))
            start = index
        }
        if !kinds.isEmpty { clusters.append(CoreCluster(kind: kinds[start], range: start..<kinds.count)) }
        return clusters
    }

    /// "4 Performance · 6 Efficiency cores", with any other cluster types
    /// after those two by letter: "… · 2 S cores". Nil when unknown.
    public static func summary(_ kinds: [CoreKind]) -> String? {
        guard !kinds.isEmpty else { return nil }
        var order: [CoreKind] = [.performance, .efficiency]
        for kind in kinds where !order.contains(kind) { order.append(kind) }
        let parts = order.compactMap { kind -> String? in
            let count = kinds.count(where: { $0 == kind })
            return count > 0 ? "\(count) \(kind.shortTitle)" : nil
        }
        return parts.joined(separator: " · ") + " cores"
    }
}

/// Logical cores `range` (in kernel order) that share one cluster type.
public struct CoreCluster: Identifiable, Equatable, Sendable {
    public let kind: CoreKind
    public let range: Range<Int>
    public var id: Int { range.lowerBound }

    public init(kind: CoreKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// The kernel's memory pressure level (`kern.memorystatus_vm_pressure_level`).
public enum MemoryPressure: Equatable, Sendable {
    case normal, warning, critical

    /// 1 normal, 2 warning, 4 critical; anything else reads as normal.
    public init(level: Int32) {
        switch level {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}

/// Physical memory split the way Activity Monitor shows it.
public struct MemoryUsage: Equatable, Sendable {
    public var total: UInt64
    /// Anonymous memory apps own, excluding what they marked purgeable.
    public var app: UInt64
    /// Kernel memory that can't be paged out.
    public var wired: UInt64
    /// Memory held by the compressor.
    public var compressed: UInt64
    /// File-backed and purgeable pages macOS can drop at once.
    public var cached: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                swapUsed: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    /// Builds the split from `vm_statistics64` page counts.
    public init(pageSize: UInt64, total: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                wiredPages: UInt64, compressorPages: UInt64, externalPages: UInt64,
                swapUsed: UInt64, pressure: MemoryPressure) {
        self.init(total: total,
                  app: (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize,
                  wired: wiredPages * pageSize,
                  compressed: compressorPages * pageSize,
                  cached: (externalPages + purgeablePages) * pageSize,
                  swapUsed: swapUsed, pressure: pressure)
    }

    /// "Memory Used" in Activity Monitor: app + wired + compressed.
    public var used: UInt64 { min(total, app + wired + compressed) }

    /// 0...1 of physical memory in use.
    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Whether two readings look the same on screen: every size rounded as
    /// `SpannerFormat.memory` shows it, the whole percent and the pressure.
    /// Byte counts change on every sample, so comparing them exactly would
    /// redraw memory views every tick on an idle Mac.
    public static func displaysSame(_ a: MemoryUsage?, _ b: MemoryUsage?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        let sizes: (MemoryUsage) -> [UInt64] = {
            [$0.total, $0.used, $0.app, $0.wired, $0.compressed, $0.cached, $0.swapUsed]
                .map(SpannerFormat.displayedMemory)
        }
        return a.pressure == b.pressure && sizes(a) == sizes(b)
            && SpannerFormat.percent(a.fraction) == SpannerFormat.percent(b.fraction)
    }
}

/// GPU activity from the accelerator's performance statistics.
public struct GPUUsage: Equatable, Sendable {
    /// 0...1 of the time the GPU was busy.
    public var utilization: Double
    /// System memory the GPU currently holds, when reported.
    public var memoryInUse: UInt64?

    public init(utilization: Double, memoryInUse: UInt64?) {
        self.utilization = utilization
        self.memoryInUse = memoryInUse
    }

    /// Reads `PerformanceStatistics` from an IOAccelerator. The keys are
    /// undocumented, so anything missing or malformed yields nil.
    public init?(performanceStatistics stats: [String: Any]) {
        guard let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { return nil }
        let memory = (stats["In use system memory"] as? NSNumber)?.uint64Value
        self.init(utilization: min(1, max(0, percent / 100)), memoryInUse: memory)
    }
}

/// One reading of the whole system, published to the UI. Percentages are
/// rounded to whole numbers so a reading that looks the same on screen
/// compares equal and doesn't trigger a redraw.
public struct SystemSnapshot: Equatable, Sendable {
    public var cpu: CPULoad?
    public var memory: MemoryUsage?
    public var gpu: GPUUsage?

    public init(cpu: CPULoad?, memory: MemoryUsage?, gpu: GPUUsage?) {
        self.cpu = cpu.map {
            CPULoad(total: Self.round($0.total), user: Self.round($0.user), system: Self.round($0.system),
                    cores: $0.cores.map(Self.round))
        }
        self.memory = memory
        self.gpu = gpu.map { GPUUsage(utilization: Self.round($0.utilization), memoryInUse: $0.memoryInUse) }
    }

    private static func round(_ fraction: Double) -> Double {
        (min(1, max(0, fraction)) * 100).rounded() / 100
    }
}

/// Fixed-size history for sparklines, oldest first.
///
/// A ring buffer: appending overwrites the oldest value in place instead of
/// shifting every element, and each sample keeps a stable id (its position
/// in the whole sequence) so charts diff one point per tick, not all of them.
public struct MetricHistory: Equatable, Sendable {
    public struct Sample: Identifiable, Equatable, Sendable {
        /// Position in everything ever appended; never reused.
        public let id: Int
        public let value: Double
    }

    public let capacity: Int
    private var storage: [Double] = []
    /// Index in `storage` of the oldest value once it is full.
    private var head = 0
    /// How many values were ever appended; the next sample's id.
    public private(set) var appendedCount = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }

    /// Values, oldest first.
    public var values: [Double] {
        guard storage.count == capacity, head > 0 else { return storage }
        var ordered: [Double] = []
        ordered.reserveCapacity(capacity)
        ordered += storage[head...]
        ordered += storage[..<head]
        return ordered
    }

    /// Values with their stable ids, oldest first.
    public var samples: [Sample] {
        let firstID = appendedCount - storage.count
        return values.enumerated().map { Sample(id: firstID + $0.offset, value: $0.element) }
    }

    public var last: Double? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }

    /// Ids a chart's x axis should span so the newest sample sits at the
    /// right edge and a partly filled history extends from there.
    public var idDomain: ClosedRange<Int> { (appendedCount - capacity)...(appendedCount - 1) }

    public mutating func append(_ value: Double) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[head] = value
            head = (head + 1) % capacity
        }
        appendedCount += 1
    }

    /// Empties the history; ids keep counting up so a chart never mistakes
    /// a new sample for an old one.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    public static func == (lhs: MetricHistory, rhs: MetricHistory) -> Bool {
        lhs.capacity == rhs.capacity && lhs.appendedCount == rhs.appendedCount && lhs.values == rhs.values
    }
}

extension SpannerFormat {
    /// Memory size in binary gigabytes, the way Activity Monitor shows it:
    /// "8.3 GB", "512 MB".
    public static func memory(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return "\(Int((Double(bytes) / 1_048_576).rounded())) MB"
    }

    /// `bytes` rounded the way `memory` shows it (0.1 GB, or whole MB), so
    /// sizes that look the same compare equal.
    public static func displayedMemory(_ bytes: UInt64) -> UInt64 {
        let unit: Double = bytes >= 1_073_741_824 ? 107_374_182.4 : 1_048_576
        return UInt64((Double(bytes) / unit).rounded() * unit)
    }

    /// Whole percent: "42%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// A process's CPU as Activity Monitor shows it, one decimal of one
    /// core, so busy apps go past 100%: "12.3%", "240.0%".
    public static func processCPU(_ fraction: Double) -> String {
        String(format: "%.1f%%", (fraction.isFinite ? max(0, fraction) : 0) * 100)
    }

    /// Decimal size, the way Finder shows file and disk sizes: "512 KB",
    /// "1.2 GB", "245 GB".
    public static func bytes(_ count: UInt64) -> String {
        byteString(Double(count))
    }

    /// Transfer rate: "0 B/s", "84 KB/s", "1.2 MB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        byteString(bytesPerSecond) + "/s"
    }

    /// `bytes` rounded to the precision `bytes(_:)` and `rate(_:)` show, so
    /// readings that look the same compare equal and don't redraw.
    public static func displayedBytes(_ bytes: Double) -> Double {
        let scaled = scaledBytes(bytes)
        return scaled.value * pow(1000, Double(scaled.unit))
    }

    /// Time since startup: "3 d 4 h", "2 h 05 min", "12 min".
    public static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 86_400 else { return duration(seconds) }
        let hours = Int(seconds / 3600)
        let days = hours / 24
        return hours % 24 == 0 ? "\(days) d" : "\(days) d \(hours % 24) h"
    }

    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    private static func byteString(_ bytes: Double) -> String {
        let scaled = scaledBytes(bytes)
        let number = scaled.decimals == 1 ? String(format: "%.1f", scaled.value) : String(Int(scaled.value))
        return "\(number) \(byteUnits[scaled.unit])"
    }

    /// The number and unit `bytes` shows as: one decimal below 10 (except
    /// plain bytes), whole numbers above, moving up a unit at 1000.
    private static func scaledBytes(_ bytes: Double) -> (value: Double, unit: Int, decimals: Int) {
        var value = bytes.isFinite ? max(0, bytes) : 0
        var unit = 0
        while true {
            let decimals = unit > 0 && value < 9.95 ? 1 : 0
            let scale = decimals == 1 ? 10.0 : 1.0
            let rounded = (value * scale).rounded() / scale
            if rounded >= 1000, unit < byteUnits.count - 1 {
                value /= 1000
                unit += 1
                continue
            }
            return (rounded, unit, decimals)
        }
    }
}
