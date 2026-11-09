import Foundation
import IOKit
import SpannerCore

/// Disk throughput from every physical drive's `IOBlockStorageDriver`
/// statistics, and capacity of the volumes Finder shows.
///
/// Keeps the matched driver services open between reads, so a read is one
/// property lookup per drive rather than a registry search; they're matched
/// again only when a read fails or volumes mount or unmount. Used from one
/// task at a time.
nonisolated final class DiskReader: @unchecked Sendable {
    /// Rates and totals from one read.
    nonisolated struct Reading: Sendable {
        /// Nil on the first read after a reset.
        var rates: ByteRates?
        /// Bytes read and written since each drive attached (startup, for
        /// the internal one).
        var totals: ByteCounters
        var driveCount: Int
    }

    private nonisolated(unsafe) var meter = RateMeter()
    private nonisolated(unsafe) var drivers: [(key: String, service: io_object_t)] = []
    private nonisolated(unsafe) var isMatched = false

    nonisolated init() {}

    deinit {
        releaseDrivers()
    }

    nonisolated func resetBaseline() {
        meter.reset()
    }

    /// Drops the cached drivers so the next read matches them afresh, after
    /// a drive is attached or ejected.
    nonisolated func invalidateDrives() {
        releaseDrivers()
    }

    /// Nil when no drive can be read.
    nonisolated func read() -> Reading? {
        if !isMatched { matchDrivers() }
        var counters: [String: ByteCounters] = [:]
        var failed = false
        for driver in drivers {
            guard let statistics = IORegistryEntryCreateCFProperty(driver.service, "Statistics" as CFString,
                                                                   kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value,
                  let written = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value else {
                failed = true
                continue
            }
            counters[driver.key] = ByteCounters(inbound: read, outbound: written)
        }
        // A drive that stopped answering was probably removed: match again
        // next time. The others still count this time.
        if failed { releaseDrivers() }
        guard !counters.isEmpty else { return nil }
        let rates = meter.update(counters, at: ProcessInfo.processInfo.systemUptime)
        return Reading(rates: rates, totals: ByteCounters.total(counters.values), driveCount: counters.count)
    }

    private nonisolated func matchDrivers() {
        releaseDrivers()
        isMatched = true
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            var id: UInt64 = 0
            guard !Self.isDiskImage(service), IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else {
                IOObjectRelease(service)
                continue
            }
            drivers.append((String(id), service))
        }
    }

    private nonisolated func releaseDrivers() {
        for driver in drivers { IOObjectRelease(driver.service) }
        drivers.removeAll()
        isMatched = false
    }

    /// Mounted disk images sit on a "Virtual Interface" device. Their I/O is
    /// also counted by the drive holding the image file, so including them
    /// would count it twice.
    private nonisolated static func isDiskImage(_ driver: io_object_t) -> Bool {
        var device: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &device) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(device) }
        let characteristics = IORegistryEntryCreateCFProperty(device, "Protocol Characteristics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        return characteristics?["Physical Interconnect"] as? String == "Virtual Interface"
    }

    // MARK: Volumes

    private nonisolated static let volumeKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeUUIDStringKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
        .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
    ]

    /// Mounted volumes as Finder's sidebar lists them, startup volume first.
    /// "Available" counts purgeable space, as Finder does. A volume ejected
    /// while it's read is skipped. Nil when the mount table can't be read.
    nonisolated static func volumes() -> [VolumeUsage]? {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys,
                                                               options: [.skipHiddenVolumes]) else { return nil }
        let keys = Set(volumeKeys)
        let volumes = urls.compactMap { url -> VolumeUsage? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  VolumeUsage.isShown(path: url.path, isLocal: values.volumeIsLocal ?? false,
                                      isBrowsable: values.volumeIsBrowsable ?? false),
                  let total = values.volumeTotalCapacity, total > 0,
                  let available = values.volumeAvailableCapacityForImportantUsage, available >= 0 else { return nil }
            return VolumeUsage(id: values.volumeUUIDString ?? url.path,
                               name: values.volumeLocalizedName ?? url.lastPathComponent,
                               isStartup: values.volumeIsRootFileSystem ?? false,
                               isInternal: values.volumeIsInternal ?? false,
                               total: UInt64(total), available: UInt64(available))
        }
        return VolumeUsage.ordered(volumes)
    }
}
