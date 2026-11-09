import Darwin
import Foundation
import IOKit
import SpannerCore

/// Reads CPU, memory and GPU load from mach and IOKit. Every read is a
/// public, unprivileged call that takes microseconds; nothing here needs
/// root or a permission prompt.
///
/// Keeps the previous CPU ticks, so it's used from one task at a time.
nonisolated final class SystemReader: @unchecked Sendable {
    /// Static facts about the Mac, read once.
    struct Hardware: Sendable {
        var cpuName: String?
        /// Kind of each logical core in kernel order; empty when unknown.
        var coreKinds: [CoreKind]
        var gpuName: String?
        /// Marketing name, "MacBook Air (13-inch, M4, 2025)", or the model
        /// identifier ("Mac16,12") when the device tree doesn't name it.
        var modelName: String?
        var physicalMemory: UInt64
        /// "macOS 26.1 (25B78)".
        var systemVersion: String
        /// From `kern.boottime`, so uptime includes time asleep (unlike
        /// `ProcessInfo.systemUptime`, which stops while the Mac sleeps).
        var bootDate: Date?
    }

    let hardware: Hardware

    private nonisolated(unsafe) var previousTicks: [CoreTicks]?
    /// The first GPU accelerator, kept open so each read is one property
    /// lookup instead of a registry search.
    private let accelerator: io_object_t

    nonisolated init() {
        accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        hardware = Hardware(cpuName: Self.sysctlString("machdep.cpu.brand_string"),
                            coreKinds: Self.coreKinds(),
                            gpuName: accelerator == 0 ? nil : Self.property("model", of: accelerator) as? String,
                            modelName: Self.productName() ?? Self.sysctlString("hw.model"),
                            physicalMemory: ProcessInfo.processInfo.physicalMemory,
                            systemVersion: Self.systemVersion(),
                            bootDate: Self.bootDate())
    }

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    /// Forgets the last CPU reading, so the next load isn't averaged over
    /// the time nobody was looking.
    nonisolated func resetCPUBaseline() {
        previousTicks = nil
    }

    /// Current reading. CPU load needs two tick readings, so it is nil on
    /// the first call after a reset.
    nonisolated func read() -> SystemSnapshot {
        SystemSnapshot(cpu: cpuLoad(), memory: Self.memory(), gpu: gpu())
    }

    // MARK: CPU

    private nonisolated func cpuLoad() -> CPULoad? {
        guard let ticks = Self.coreTicks() else { return nil }
        defer { previousTicks = ticks }
        return previousTicks.flatMap { CPULoad(from: $0, to: ticks) }
    }

    private nonisolated static func coreTicks() -> [CoreTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[core * states + Int(state)]) }
            return CoreTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                             idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }

    /// Core kinds from the device tree's one-letter `cluster-type` ("E", "P",
    /// and on newer chips others) on each cpu node, ordered by
    /// `logical-cpu-id`. Empty on Intel Macs.
    private nonisolated static func coreKinds() -> [CoreKind] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var kinds: [(id: Int, kind: CoreKind)] = []
        while case let cpu = IOIteratorNext(iterator), cpu != 0 {
            defer { IOObjectRelease(cpu) }
            guard let id = (property("logical-cpu-id", of: cpu) as? NSNumber)?.intValue,
                  let cluster = property("cluster-type", of: cpu) as? Data,
                  let letter = cluster.first, letter != 0 else { continue }
            kinds.append((id, CoreKind(clusterType: String(UnicodeScalar(letter)))))
        }
        // Partial or gapped data would label the wrong bars, so show none.
        let sorted = kinds.sorted { $0.id < $1.id }
        guard sorted.map(\.id) == Array(0..<sorted.count) else { return [] }
        return sorted.map(\.kind)
    }

    // MARK: Load and static facts

    /// 1, 5 and 15 minute load averages; nil if the kernel doesn't answer.
    nonisolated static func loadAverage() -> LoadAverage? {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else { return nil }
        return LoadAverage(values)
    }

    /// The device tree's `product-name`, which macOS shows in About This Mac.
    /// Present on Apple silicon; Intel Macs fall back to `hw.model`.
    private nonisolated static func productName() -> String? {
        let product = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard product != 0 else { return nil }
        defer { IOObjectRelease(product) }
        guard let data = property("product-name", of: product) as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private nonisolated static func systemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        if let build = sysctlString("kern.osversion") { text += " (\(build))" }
        return text
    }

    private nonisolated static func bootDate() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    // MARK: Memory

    private nonisolated static func memory() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let pressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
            ? MemoryPressure(level: level) : .normal

        return MemoryUsage(pageSize: UInt64(getpagesize()), total: ProcessInfo.processInfo.physicalMemory,
                           internalPages: UInt64(stats.internal_page_count),
                           purgeablePages: UInt64(stats.purgeable_count),
                           wiredPages: UInt64(stats.wire_count),
                           compressorPages: UInt64(stats.compressor_page_count),
                           externalPages: UInt64(stats.external_page_count),
                           swapUsed: swapUsed, pressure: pressure)
    }

    // MARK: GPU

    private nonisolated func gpu() -> GPUUsage? {
        guard accelerator != 0,
              let stats = Self.property("PerformanceStatistics", of: accelerator) as? [String: Any] else { return nil }
        return GPUUsage(performanceStatistics: stats)
    }

    // MARK: Helpers

    private nonisolated static func property(_ key: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
