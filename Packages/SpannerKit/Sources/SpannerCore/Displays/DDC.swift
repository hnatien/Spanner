import Foundation

/// DDC/CI packet encoding for external monitors (VESA MCCS), as sent over
/// IOAVService I2C on Apple Silicon. The layout and checksums follow
/// MonitorControl's Arm64DDC, which is the de facto reference.
public enum DDC {
    /// 7-bit I2C address of the display's DDC/CI endpoint.
    public static let chipAddress: UInt8 = 0x37
    /// Sub-address of the host ("source") for writes.
    public static let dataAddress: UInt8 = 0x51
    /// Length of a Get VCP Feature reply.
    public static let replyLength = 11

    /// VCP feature codes Spanner uses.
    public enum Feature: UInt8, Sendable, CaseIterable {
        case brightness = 0x10
        case contrast = 0x12
        case volume = 0x62
        case mute = 0x8D
    }

    /// Set VCP Feature: `[0x84, 0x03, code, hi, lo, checksum]`.
    public static func setPacket(_ feature: Feature, value: UInt16) -> [UInt8] {
        packet([feature.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Get VCP Feature request: `[0x82, 0x01, code, checksum]`.
    public static func getPacket(_ feature: Feature) -> [UInt8] {
        packet([feature.rawValue])
    }

    /// The length byte doubles as the opcode: one payload byte is a Get
    /// (0x01), three are a Set (0x03). Get requests are checksummed from the
    /// destination address alone, Sets from destination XOR source, matching
    /// what monitors in the field accept.
    static func packet(_ payload: [UInt8]) -> [UInt8] {
        var bytes = [0x80 | UInt8(payload.count + 1), UInt8(payload.count)] + payload
        let initial = payload.count == 1 ? chipAddress << 1 : (chipAddress << 1) ^ dataAddress
        bytes.append(checksum(initial, bytes))
        return bytes
    }

    static func checksum(_ initial: UInt8, _ bytes: some Collection<UInt8>) -> UInt8 {
        bytes.reduce(initial, ^)
    }

    /// A parsed Get VCP reply.
    public struct Reading: Equatable, Sendable {
        public let current: UInt16
        public let maximum: UInt16

        public init(current: UInt16, maximum: UInt16) {
            self.current = current
            self.maximum = maximum
        }

        /// Current value as a 0...1 fraction of the maximum.
        public var fraction: Double {
            maximum == 0 ? 0 : min(1, Double(current) / Double(maximum))
        }
    }

    /// Parses an 11-byte reply. Rejects bad checksums, error result codes,
    /// replies for a different feature, and an all-zero buffer (what a
    /// failed read leaves behind).
    public static func parseReply(_ reply: [UInt8], for feature: Feature) -> Reading? {
        guard reply.count == replyLength, reply.contains(where: { $0 != 0 }) else { return nil }
        guard checksum(0x50, reply.prefix(replyLength - 1)) == reply[replyLength - 1] else { return nil }
        // [src, len, 0x02 opcode, result, code, type, maxHi, maxLo, curHi, curLo, chk]
        guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == feature.rawValue else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return Reading(current: current, maximum: maximum)
    }

    /// Raw value for a 0...1 fraction of `maximum`.
    public static func value(for fraction: Double, maximum: UInt16) -> UInt16 {
        UInt16((min(max(fraction, 0), 1) * Double(maximum)).rounded())
    }
}

/// Pairs external displays from CoreGraphics with the IORegistry AV services
/// that can talk DDC to them.
public enum DisplayServiceMatcher {
    /// What CoreGraphics says about a display.
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let vendor: UInt32
        public let model: UInt32
        public let serial: UInt32
        public let name: String

        public init(id: UInt32, vendor: UInt32, model: UInt32, serial: UInt32, name: String) {
            self.id = id
            self.vendor = vendor
            self.model = model
            self.serial = serial
            self.name = name
        }
    }

    /// What the framebuffer in front of an external AV service says about
    /// its display (`DisplayAttributes.ProductAttributes`).
    public struct Service: Equatable, Sendable {
        public let index: Int
        public let vendor: UInt32?
        public let serial: UInt32?
        public let name: String?

        public init(index: Int, vendor: UInt32?, serial: UInt32?, name: String?) {
            self.index = index
            self.vendor = vendor
            self.serial = serial
            self.name = name
        }
    }

    /// Returns display ID → service index. Pairs whose vendor or serial
    /// disagree are never matched; the rest are scored (vendor +1, serial +4,
    /// name +2) and assigned greedily from the best score down, ties going
    /// to display order then registry order.
    public static func match(displays: [Display], services: [Service]) -> [UInt32: Int] {
        var scored: [(score: Int, order: Int, display: UInt32, service: Int)] = []
        for (order, display) in displays.enumerated() {
            for service in services {
                if let vendor = service.vendor, vendor != display.vendor { continue }
                var score = 0
                if service.vendor != nil { score += 1 }
                if let serial = service.serial, serial != 0, display.serial != 0 {
                    if serial != display.serial { continue }
                    score += 4
                }
                if let name = service.name, !name.isEmpty {
                    if name.caseInsensitiveCompare(display.name) == .orderedSame { score += 2 }
                }
                scored.append((score, order, display.id, service.index))
            }
        }
        scored.sort { ($1.score, $0.order, $0.service) < ($0.score, $1.order, $1.service) }
        var result: [UInt32: Int] = [:]
        var used = Set<Int>()
        for candidate in scored {
            guard result[candidate.display] == nil, !used.contains(candidate.service) else { continue }
            result[candidate.display] = candidate.service
            used.insert(candidate.service)
        }
        return result
    }
}
