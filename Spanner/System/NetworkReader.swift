import Darwin
import Foundation
import SpannerCore
import SystemConfiguration

/// Network throughput summed over the physical, active interfaces.
///
/// One `sysctl` `NET_RT_IFLIST2` call lists the interfaces with their flags
/// and type. Their byte counters come from the interface MIB
/// (`IFMIB_IFDATA`/`IFDATA_GENERAL`), one call per counted interface, as
/// `netstat -ib` reads them: on macOS 27 the `if_data64` counters in the
/// `NET_RT_IFLIST2` dump are truncated to 32 bits and rounded to the KB
/// (measured: 614 MB there against 47.9 GB in the MIB), and the `getifaddrs`
/// ones are 32-bit too. Keeps the previous counters and its buffer, so it's
/// used from one task at a time.
nonisolated final class NetworkReader: @unchecked Sendable {
    /// Rates, totals and which interfaces they cover, from one read.
    nonisolated struct Reading: Sendable {
        /// Nil on the first read after a reset.
        var rates: ByteRates?
        /// Bytes received and sent by the counted interfaces since they
        /// came up (usually since startup).
        var totals: ByteCounters
        /// BSD names, sorted, so a change can refresh the interface label.
        var interfaces: [String]
    }

    /// `IFT_IEEE80211` from <net/if_types.h>, which Swift doesn't import.
    /// macOS reports Wi-Fi as Ethernet, but other drivers may not.
    private nonisolated static let ieee80211Type: Int32 = 0x47
    /// From <net/if_mib.h>, which Swift doesn't import.
    private nonisolated static let netlinkGeneric: Int32 = 0, ifmibIfData: Int32 = 2, ifDataGeneral: Int32 = 1

    private nonisolated(unsafe) var meter = RateMeter()
    /// Reused between reads: the routing table dump is a few KB.
    private nonisolated(unsafe) var buffer: [UInt8] = []

    nonisolated init() {}

    nonisolated func resetBaseline() {
        meter.reset()
    }

    /// Nil when the kernel can't be read; a reading with no interfaces when
    /// nothing is connected.
    nonisolated func read() -> Reading? {
        guard let counters = interfaceCounters() else { return nil }
        let rates = meter.update(counters, at: ProcessInfo.processInfo.systemUptime)
        return Reading(rates: rates, totals: ByteCounters.total(counters.values), interfaces: counters.keys.sorted())
    }

    private nonisolated func interfaceCounters() -> [String: ByteCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        // Headroom for interfaces that appear between the two calls; if the
        // table still outgrows it, this read fails and the next one resizes.
        if buffer.count < size { buffer = [UInt8](repeating: 0, count: size + size / 4) }
        size = buffer.count
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        let interfaces = buffer.withUnsafeBytes { Self.countedInterfaces(in: $0, length: min(size, $0.count)) }
        var counters: [String: ByteCounters] = [:]
        counters.reserveCapacity(interfaces.count)
        // An interface that vanished since the listing just drops out.
        for interface in interfaces {
            if let data = Self.interfaceData(index: interface.index) {
                counters[interface.name] = ByteCounters(inbound: data.ifi_ibytes, outbound: data.ifi_obytes)
            }
        }
        return counters
    }

    /// Full 64-bit counters for one interface from the interface MIB.
    private nonisolated static func interfaceData(index: UInt16) -> if_data64? {
        var mib: [Int32] = [CTL_NET, PF_LINK, netlinkGeneric, ifmibIfData, Int32(index), ifDataGeneral]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return data.ifmd_data
    }

    /// Walks the `RTM_IFINFO2` messages for interfaces that count. Each is an
    /// `if_msghdr2` followed by the interface's `sockaddr_dl`, which carries
    /// its name.
    private nonisolated static func countedInterfaces(in raw: UnsafeRawBufferPointer,
                                                      length: Int) -> [(name: String, index: UInt16)] {
        var interfaces: [(name: String, index: UInt16)] = []
        let headerSize = MemoryLayout<if_msghdr>.size
        let messageSize = MemoryLayout<if_msghdr2>.size
        // sockaddr_dl: sdl_nlen is byte 5, the name starts at byte 8.
        let nameLengthOffset = 5, nameOffset = 8
        var offset = 0
        while offset + headerSize <= length {
            let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }
            defer { offset += messageLength }
            guard Int32(header.ifm_type) == RTM_IFINFO2, messageLength >= messageSize + nameOffset else { continue }

            let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
            let address = offset + messageSize
            let nameLength = Int(raw[address + nameLengthOffset])
            guard nameLength > 0, address + nameOffset + nameLength <= offset + messageLength else { continue }
            let name = String(decoding: UnsafeRawBufferPointer(rebasing: raw[(address + nameOffset)..<(address + nameOffset + nameLength)]),
                              as: UTF8.self)

            let flags = message.ifm_flags
            let type = Int32(message.ifm_data.ifi_type)
            guard NetworkInterfaceFilter.counts(
                name: name,
                isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                isLoopback: flags & IFF_LOOPBACK != 0,
                isPhysicalType: type == IFT_ETHER || type == Self.ieee80211Type || type == IFT_CELLULAR
            ) else { continue }
            interfaces.append((name, message.ifm_index))
        }
        return interfaces
    }

    // MARK: Primary interface

    /// The interface carrying the default route, with the name System
    /// Settings gives it and its IPv4 address. Changes rarely, so it's read
    /// on the slow lane and when the set of interfaces changes, not per tick.
    nonisolated static func primaryInterface() -> NetworkInterfaceInfo? {
        guard let store = SCDynamicStoreCreate(nil, "Spanner" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = global["PrimaryInterface"] as? String else { return nil }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let displayName = interfaces
            .first { SCNetworkInterfaceGetBSDName($0) as String? == name }
            .flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
        return NetworkInterfaceInfo(name: name, displayName: displayName, ipv4: ipv4Address(of: name))
    }

    private nonisolated static func ipv4Address(of interface: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == interface else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let result = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inet in
                var ip = inet.pointee.sin_addr
                return inet_ntop(AF_INET, &ip, &text, socklen_t(text.count))
            }
            guard result != nil else { continue }
            return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
}
