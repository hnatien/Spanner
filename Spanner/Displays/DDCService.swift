import Foundation
import IOKit
import OSLog
import SpannerCore

// Private IOKit calls for DDC over I2C on Apple Silicon, as MonitorControl
// and Lunar use them. Phase 2 confirmed all three resolve on macOS 27.2.

@_silgen_name("IOAVServiceCreateWithService")
nonisolated func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
nonisolated func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
                                    _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
nonisolated func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
                                     _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

/// Finds the AV services of external displays in the IORegistry.
enum DDCServiceFinder {
    struct Found {
        let attributes: DisplayServiceMatcher.Service
        let channel: DDCChannel
    }

    /// Walks the service plane in order. Each external `DCPAVServiceProxy`
    /// follows the framebuffer (`IOMobileFramebufferShim` or `AppleCLCD2`)
    /// that drives it, whose `DisplayAttributes` identify the monitor.
    static func externalServices() -> [Found] {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively),
                                       &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [Found] = []
        var pending: (vendor: UInt32?, serial: UInt32?, name: String?)?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if IOObjectConformsTo(entry, "IOMobileFramebufferShim") != 0 || IOObjectConformsTo(entry, "AppleCLCD2") != 0 {
                pending = framebufferAttributes(entry)
                continue
            }
            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                  property(entry, "Location") as? String == "External" else { continue }
            // Consume the framebuffer's attributes so a later proxy without
            // its own framebuffer isn't given the wrong monitor's identity.
            let attributes = pending ?? (nil, nil, nil)
            pending = nil
            guard let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            found.append(Found(attributes: .init(index: found.count, vendor: attributes.vendor,
                                                 serial: attributes.serial, name: attributes.name),
                               channel: DDCChannel(service: service)))
        }
        return found
    }

    private static func framebufferAttributes(_ entry: io_registry_entry_t) -> (vendor: UInt32?, serial: UInt32?, name: String?) {
        guard let display = property(entry, "DisplayAttributes") as? [String: Any],
              let product = display["ProductAttributes"] as? [String: Any] else { return (nil, nil, nil) }
        let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value
        let serial = (product["SerialNumber"] as? NSNumber)?.uint32Value
        return (vendor, serial, product["ProductName"] as? String)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Talks DDC/CI to one monitor on a private serial queue. I2C is slow (tens
/// of milliseconds per transaction, with retries), so nothing here runs on
/// the main thread. Slider drags send many writes; only the latest value per
/// feature is kept while a write is in flight.
nonisolated final class DDCChannel: @unchecked Sendable {
    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "dev.spanner.ddc")
    private let lock = NSLock()
    private nonisolated(unsafe) var pendingWrites: [DDC.Feature: UInt16] = [:]
    private nonisolated(unsafe) var isDraining = false
    private static let log = Logger(subsystem: "dev.spanner.Spanner", category: "DDC")

    // Timings from MonitorControl's Arm64DDC defaults, in microseconds.
    private static let writeDelay: useconds_t = 10_000
    private static let readDelay: useconds_t = 50_000
    private static let retryDelay: useconds_t = 20_000
    private static let attempts = 5

    nonisolated init(service: CFTypeRef) {
        self.service = service
    }

    /// Reads a feature's current and maximum value, or nil if the monitor
    /// doesn't answer (many don't support reads, or not every feature).
    nonisolated func read(_ feature: DDC.Feature) async -> DDC.Reading? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.performRead(feature)) }
        }
    }

    /// Queues a write; earlier queued values for the same feature are dropped.
    nonisolated func write(_ feature: DDC.Feature, value: UInt16) {
        lock.lock()
        pendingWrites[feature] = value
        let shouldStart = !isDraining
        isDraining = true
        lock.unlock()
        if shouldStart { queue.async { self.drain() } }
    }

    private nonisolated func drain() {
        while true {
            lock.lock()
            guard let (feature, value) = pendingWrites.first else {
                isDraining = false
                lock.unlock()
                return
            }
            pendingWrites[feature] = nil
            lock.unlock()
            if !performWrite(DDC.setPacket(feature, value: value)) {
                Self.log.debug("DDC write of \(feature.rawValue) failed")
            }
        }
    }

    private nonisolated func performWrite(_ packet: [UInt8]) -> Bool {
        var bytes = packet
        for _ in 0..<Self.attempts {
            // Monitors often miss a single write, so each attempt sends twice.
            var ok = true
            for _ in 0..<2 {
                usleep(Self.writeDelay)
                ok = IOAVServiceWriteI2C(service, UInt32(DDC.chipAddress), UInt32(DDC.dataAddress),
                                         &bytes, UInt32(bytes.count)) == kIOReturnSuccess && ok
            }
            if ok { return true }
            usleep(Self.retryDelay)
        }
        return false
    }

    private nonisolated func performRead(_ feature: DDC.Feature) -> DDC.Reading? {
        var request = DDC.getPacket(feature)
        for _ in 0..<Self.attempts {
            usleep(Self.writeDelay)
            guard IOAVServiceWriteI2C(service, UInt32(DDC.chipAddress), UInt32(DDC.dataAddress),
                                      &request, UInt32(request.count)) == kIOReturnSuccess else {
                usleep(Self.retryDelay)
                continue
            }
            usleep(Self.readDelay)
            var reply = [UInt8](repeating: 0, count: DDC.replyLength)
            if IOAVServiceReadI2C(service, UInt32(DDC.chipAddress), 0, &reply, UInt32(reply.count)) == kIOReturnSuccess,
               let reading = DDC.parseReply(reply, for: feature) {
                return reading
            }
            usleep(Self.retryDelay)
        }
        return nil
    }
}
