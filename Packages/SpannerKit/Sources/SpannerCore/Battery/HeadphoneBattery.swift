import Foundation

/// Battery of connected Bluetooth headphones (AirPods, Beats), read from
/// IOBluetooth. AirPods report each bud and the case separately; single-
/// battery headphones (AirPods Max, most Beats) report one level.
public struct HeadphoneBattery: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case airPods, airPodsPro, airPodsMax, other
    }

    /// Bluetooth address.
    public let id: String
    public let name: String
    public let left: Int?
    public let right: Int?
    public let chargingCase: Int?
    public let single: Int?
    /// Whether the headphones are being worn; nil when the device has no
    /// ear detection or the person turned Automatic Ear Detection off.
    public let isInEar: Bool?
    public let kind: Kind

    /// IOBluetooth reports 0 for a level it doesn't know (a bud in a closed
    /// case, or before the first battery report after connecting).
    public init(id: String, name: String, left: Int = 0, right: Int = 0, chargingCase: Int = 0,
                single: Int = 0, isInEar: Bool? = nil) {
        func level(_ value: Int) -> Int? { value > 0 ? min(100, value) : nil }
        self.id = id
        self.name = name
        self.left = level(left)
        self.right = level(right)
        self.chargingCase = level(chargingCase)
        self.single = level(single)
        self.isInEar = isInEar
        let lowered = name.lowercased()
        kind = lowered.contains("airpods pro") ? .airPodsPro
            : lowered.contains("airpods max") ? .airPodsMax
            : lowered.contains("airpods") ? .airPods
            : .other
    }

    /// The level that runs out first, ignoring the case: what the person can
    /// still listen for.
    public var lowest: Int? {
        [left, right, single].compactMap(\.self).min()
    }

    public var hasBattery: Bool { lowest != nil || chargingCase != nil }

    public var level: ChargeLevel? { lowest.map(ChargeLevel.init(percent:)) }

    /// "L 80% · R 75% · Case 40%", or "60%" for single-battery headphones.
    public var summary: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if left == nil, right == nil, let single { parts.append("\(single)%") }
        if let chargingCase { parts.append("Case \(chargingCase)%") }
        return parts.joined(separator: " · ")
    }
}

/// Decides when the person starts using their headphones, so Spanner can
/// show the battery at that moment.
///
/// Headphones count as in use once they're connected, report a battery level
/// and are in an ear (or just connected, when ear detection is off). Taking
/// them out briefly, or a short Bluetooth dropout, doesn't count as a new
/// session: usage must have stopped for `rearmDelay` first.
public struct HeadphoneUsageDetector: Sendable {
    public static let rearmDelay: TimeInterval = 5 * 60

    private var inUse: Set<String> = []
    private var stoppedAt: [String: Date] = [:]
    private var hasBaseline = false

    public init() {}

    /// Feeds the currently connected headphones and returns the ones the
    /// person just started using. The first call only records the state, so
    /// headphones already in use when Spanner launches don't trigger.
    public mutating func update(_ headphones: [HeadphoneBattery], now: Date) -> [HeadphoneBattery] {
        let current = Set(headphones.filter(Self.isInUse).map(\.id))
        for id in inUse.subtracting(current) {
            stoppedAt[id] = now
        }
        defer {
            inUse = current
            hasBaseline = true
        }
        guard hasBaseline else { return [] }

        return headphones.filter { headphone in
            guard current.contains(headphone.id), !inUse.contains(headphone.id) else { return false }
            guard let stopped = stoppedAt[headphone.id] else { return true }
            return now.timeIntervalSince(stopped) >= Self.rearmDelay
        }
    }

    private static func isInUse(_ headphone: HeadphoneBattery) -> Bool {
        headphone.hasBattery && headphone.isInEar != false
    }
}
