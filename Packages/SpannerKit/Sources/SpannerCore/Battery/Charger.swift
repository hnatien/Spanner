import Foundation

/// One USB-C Power Delivery voltage/current offer from the charger.
public struct PDProfile: Equatable, Sendable, Identifiable {
    public let index: Int
    /// Millivolts and milliamps.
    public let voltage: Int
    public let current: Int

    public var id: Int { index }
    public var watts: Double { Double(voltage) * Double(current) / 1_000_000 }

    public init(index: Int, voltage: Int, current: Int) {
        self.index = index
        self.voltage = voltage
        self.current = current
    }
}

/// The connected power adapter, from `AppleSmartBattery.AdapterDetails`.
public struct ChargerInfo: Equatable, Sendable {
    /// Rated watts as reported by macOS.
    public var watts: Int?
    /// Raw description, e.g. "pd charger".
    public var description: String?
    /// Negotiated millivolts and milliamps.
    public var voltage: Int?
    public var current: Int?
    public var isWireless: Bool
    public var profiles: [PDProfile]
    public var activeProfileIndex: Int?

    public init(watts: Int?, description: String?, voltage: Int?, current: Int?, isWireless: Bool = false,
                profiles: [PDProfile] = [], activeProfileIndex: Int? = nil) {
        self.watts = watts
        self.description = description
        self.voltage = voltage
        self.current = current
        self.isWireless = isWireless
        self.profiles = profiles
        self.activeProfileIndex = activeProfileIndex
    }

    /// Returns nil for an empty AdapterDetails dictionary (no adapter).
    public init?(adapterDetails details: PropertyBag) {
        let watts = details.int("Watts")
        let voltage = details.int("AdapterVoltage")
        guard (watts ?? 0) > 0 || (voltage ?? 0) > 0 else { return nil }
        self.watts = watts
        description = details.string("Description") ?? details.string("Name")
        self.voltage = voltage
        current = details.int("Current")
        isWireless = details.bool("IsWireless") ?? false
        profiles = details.bags("UsbHvcMenu").compactMap { entry in
            guard let index = entry.int("Index"), let voltage = entry.int("MaxVoltage"),
                  let current = entry.int("MaxCurrent") else { return nil }
            return PDProfile(index: index, voltage: voltage, current: current)
        }
        activeProfileIndex = details.int("UsbHvcHvcIndex")
    }

    public var activeProfile: PDProfile? {
        profiles.first { $0.index == activeProfileIndex }
    }

    public var isUSBPowerDelivery: Bool {
        !profiles.isEmpty || (description?.lowercased().contains("pd") ?? false)
    }

    /// Display name, e.g. "34 W USB-C" or "MagSafe charger".
    public var displayName: String {
        let kind = isWireless ? "Wireless" : isUSBPowerDelivery ? "USB-C" : "Charger"
        if let watts, watts > 0 { return "\(watts) W \(kind)" }
        return kind
    }

    /// Negotiated electrical values, e.g. "20 V × 1.70 A".
    public var negotiatedText: String? {
        guard let voltage, let current else { return nil }
        return "\(BatteryFormat.volts(voltage, digits: 0)) × \(BatteryFormat.amps(current))"
    }
}

/// Live power accounting from `AppleSmartBattery.PowerTelemetryData`
/// (macOS 13+). All values are milliwatts.
public struct PowerTelemetry: Equatable, Sendable {
    /// Power drawn from the adapter.
    public var systemPowerIn: Int?
    /// Power the Mac itself is using.
    public var systemLoad: Int?
    /// Power into (+) or out of (−) the battery.
    public var batteryPower: Int?
    /// Power lost converting the adapter's voltage.
    public var adapterEfficiencyLoss: Int?

    public init(systemPowerIn: Int?, systemLoad: Int?, batteryPower: Int?, adapterEfficiencyLoss: Int? = nil) {
        self.systemPowerIn = systemPowerIn
        self.systemLoad = systemLoad
        self.batteryPower = batteryPower
        self.adapterEfficiencyLoss = adapterEfficiencyLoss
    }

    public init(properties: PropertyBag) {
        systemPowerIn = properties.int("SystemPowerIn")
        systemLoad = properties.int("SystemLoad")
        batteryPower = properties.int("BatteryPower")
        adapterEfficiencyLoss = properties.int("AdapterEfficiencyLoss")
    }
}
