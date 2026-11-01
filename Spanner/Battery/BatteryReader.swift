import CSMC
import Foundation
import IOKit
import IOKit.ps
import SpannerCore

/// Reads battery data from IOKit and the SMC. All reads are public,
/// unprivileged APIs; nothing here needs root or a permission prompt.
final class BatteryReader {
    private var smcConnection: UInt32 = 0
    private var smcOpen = false

    /// Battery temperature sensors. macOS 27 dropped `Temperature` from
    /// AppleSmartBattery, but these SMC keys are readable without root.
    private static let temperatureKeys = ["TB1T", "TB2T"]

    func open() {
        guard !smcOpen else { return }
        smcOpen = smc_open(&smcConnection)
    }

    func close() {
        guard smcOpen else { return }
        smc_close(smcConnection)
        smcOpen = false
    }

    deinit {
        if smcOpen { smc_close(smcConnection) }
    }

    /// Current snapshot, or nil when the Mac has no battery.
    func snapshot() -> BatterySnapshot? {
        guard let registry = Self.registryProperties() else { return nil }
        var snapshot = BatterySnapshot(registry: PropertyBag(registry),
                                       powerSource: Self.internalPowerSource().map(PropertyBag.init))
        snapshot?.temperature = temperature()
        if snapshot?.charger != nil {
            snapshot?.charger?.isMagSafe = ChargerInfo.magSafeConnected(ports: Self.portProperties().map(PropertyBag.init))
        }
        return snapshot
    }

    private func temperature() -> Double? {
        guard smcOpen else { return nil }
        let readings = Self.temperatureKeys.compactMap { key -> Double? in
            var value = 0.0
            let ok = key.withCString { smc_read_number(smcConnection, $0, &value) }
            // Discard implausible values (missing sensors can read 0 or junk).
            return ok && value > -20 && value < 120 && value != 0 ? value : nil
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return properties
    }

    /// Properties of the Mac's built-in USB-C and MagSafe ports.
    private static func portProperties() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccessoryManager"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }
            ports.append(properties)
        }
        return ports
    }

    /// The IOPowerSources description of the internal battery.
    private static func internalPowerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return description
            }
        }
        return nil
    }

    /// Apple accessories that report a battery level (Magic Keyboard, Mouse,
    /// Trackpad). They publish `BatteryPercent` on their HID event service.
    static func accessories() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [AccessoryBattery] = []
        var seen = Set<String>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            let bag = PropertyBag(properties)
            // One device can expose several HID services; keep one per serial/name.
            let key = bag.string("SerialNumber") ?? bag.string("Product") ?? String(entryID)
            guard !seen.contains(key), let accessory = AccessoryBattery(id: key, properties: bag) else { continue }
            seen.insert(key)
            found.append(accessory)
        }
        return found.sorted { $0.name < $1.name }
    }
}
