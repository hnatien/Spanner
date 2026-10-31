import Foundation

/// Overall charging state, derived from the registry flags.
public enum BatteryState: Equatable, Sendable {
    case charging
    case discharging
    case pluggedNotCharging
    case full
}

/// Charge level band used for colour and warnings.
public enum ChargeLevel: Equatable, Sendable {
    case critical  // below 10%
    case low       // below 20%
    case normal

    public init(percent: Int) {
        self = percent < 10 ? .critical : percent < 20 ? .low : .normal
    }
}

/// One reading of the internal battery, parsed from the `AppleSmartBattery`
/// IORegistry entry plus the IOPowerSources description.
///
/// Every field that a given Mac or macOS version may omit is optional, so the
/// UI can hide what it doesn't know instead of showing zeros.
public struct BatterySnapshot: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool
    public var optimizedChargingEngaged: Bool

    public var cycleCount: Int?
    public var designCycleCount: Int?

    /// Capacities in mAh. `maxCapacity` is the raw full-charge capacity.
    public var designCapacity: Int?
    public var maxCapacity: Int?
    public var nominalCapacity: Int?
    public var currentCapacity: Int?

    /// Millivolts and signed milliamps (positive into the battery).
    public var voltage: Int?
    public var amperage: Int?

    public var minutesToFull: Int?
    public var minutesToEmpty: Int?

    /// `ChargerData.NotChargingReason`; nil or 0 when nothing is blocking.
    public var notChargingReason: Int?

    /// Degrees Celsius. Not in the registry on macOS 27; filled from the SMC.
    public var temperature: Double?

    public var charger: ChargerInfo?
    public var telemetry: PowerTelemetry?

    public init(percent: Int, isCharging: Bool, isPluggedIn: Bool, isFullyCharged: Bool = false,
                optimizedChargingEngaged: Bool = false) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
        self.optimizedChargingEngaged = optimizedChargingEngaged
    }

    /// The registry uses 65535 for "not known yet"; IOPowerSources uses -1.
    static func minutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }

    /// Parses a snapshot. Returns nil when the dictionary describes no
    /// installed battery (desktop Macs have no `AppleSmartBattery` data).
    ///
    /// - Parameters:
    ///   - registry: properties of the `AppleSmartBattery` service.
    ///   - powerSource: the internal battery's IOPowerSources description.
    public init?(registry: PropertyBag, powerSource: PropertyBag? = nil) {
        if registry.bool("BatteryInstalled") == false { return nil }
        guard let percent = registry.int("CurrentCapacity") ?? powerSource?.int("Current Capacity") else { return nil }

        self.percent = min(100, max(0, percent))
        isPluggedIn = registry.bool("ExternalConnected") ?? (powerSource?.string("Power Source State") == "AC Power")
        isCharging = registry.bool("IsCharging") ?? powerSource?.bool("Is Charging") ?? false
        isFullyCharged = registry.bool("FullyCharged") ?? powerSource?.bool("Is Charged") ?? false
        optimizedChargingEngaged = powerSource?.bool("Optimized Battery Charging Engaged") ?? false

        // On macOS 27 the capacities exist only inside the nested
        // `BatteryData` dictionary; older releases had them at the top level.
        let batteryData = registry.bag("BatteryData")
        func capacity(_ key: String) -> Int? { registry.int(key) ?? batteryData?.int(key) }

        cycleCount = registry.int("CycleCount") ?? batteryData?.int("CycleCount")
        designCycleCount = registry.int("DesignCycleCount9C")
        designCapacity = capacity("DesignCapacity")
        maxCapacity = capacity("AppleRawMaxCapacity") ?? capacity("NominalChargeCapacity")
        nominalCapacity = capacity("NominalChargeCapacity")
        currentCapacity = capacity("AppleRawCurrentCapacity")
        voltage = registry.int("Voltage")
        amperage = registry.int("InstantAmperage") ?? registry.int("Amperage")

        // IOPowerSources' estimates are the ones macOS shows in the menu bar;
        // fall back to the registry averages when it is still calculating.
        minutesToFull = Self.minutes(powerSource?.int("Time to Full Charge")) ?? Self.minutes(registry.int("AvgTimeToFull"))
        minutesToEmpty = Self.minutes(powerSource?.int("Time to Empty")) ?? Self.minutes(registry.int("AvgTimeToEmpty"))

        notChargingReason = registry.bag("ChargerData")?.int("NotChargingReason")
        charger = isPluggedIn ? registry.bag("AdapterDetails").flatMap(ChargerInfo.init(adapterDetails:)) : nil
        telemetry = registry.bag("PowerTelemetryData").map(PowerTelemetry.init(properties:))
    }

    public var state: BatteryState {
        if isCharging { return .charging }
        guard isPluggedIn else { return .discharging }
        return isFullyCharged || percent >= 100 ? .full : .pluggedNotCharging
    }

    public var level: ChargeLevel { ChargeLevel(percent: percent) }

    /// Raw full-charge capacity as a fraction of the design capacity. This is
    /// not Apple's "Maximum Capacity" figure, which is computed differently.
    public var health: Double? {
        guard let maxCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Double(maxCapacity) / Double(designCapacity)
    }

    /// Cycles used as a fraction of the rated cycle count.
    public var cycleFraction: Double? {
        guard let cycleCount, let designCycleCount, designCycleCount > 0 else { return nil }
        return Double(cycleCount) / Double(designCycleCount)
    }

    /// Battery power in watts, positive while charging. Prefers the
    /// telemetry figure; otherwise volts × amps.
    public var batteryWatts: Double? {
        if let power = telemetry?.batteryPower { return Double(power) / 1000 }
        guard let voltage, let amperage else { return nil }
        return Double(voltage) * Double(amperage) / 1_000_000
    }

    /// Short status line for the hero card and menu bar.
    public var statusText: String {
        switch state {
        case .charging:
            if let minutes = minutesToFull { return "Charging · \(SpannerFormat.duration(Double(minutes) * 60)) to full" }
            return "Charging"
        case .discharging:
            if let minutes = minutesToEmpty { return "On battery · \(SpannerFormat.duration(Double(minutes) * 60)) left" }
            return "On battery"
        case .full:
            return "Fully charged"
        case .pluggedNotCharging:
            return "Plugged in, not charging"
        }
    }

    /// Why the Mac is plugged in but not charging, when that can be told.
    public var notChargingExplanation: String? {
        guard state == .pluggedNotCharging else { return nil }
        if let reason = notChargingReason, reason != 0 {
            return Self.explanation(forNotChargingReason: reason)
        }
        if optimizedChargingEngaged {
            return "Optimized Charging is holding the charge to reduce battery wear."
        }
        return "macOS is pausing charging, for example because of a charge limit set in System Settings."
    }

    /// Text for a `ChargerData.NotChargingReason` code. Apple doesn't document
    /// these; 0x1000 was observed when charging was cut off in software.
    public static func explanation(forNotChargingReason reason: Int) -> String {
        switch reason {
        case 0x1000: "Charging was turned off by software (another battery app or a charge limit)."
        default: "macOS reports charging is paused (code 0x\(String(reason, radix: 16)))."
        }
    }
}
