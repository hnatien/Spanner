import Foundation

/// Where power is going right now, in watts: charger → Mac → battery.
public struct PowerFlow: Equatable, Sendable {
    public enum BatteryDirection: Equatable, Sendable {
        case charging     // Mac → battery
        case discharging  // battery → Mac
        case idle
    }

    /// Watts drawn from the charger; nil when unplugged or unknown.
    public var adapterWatts: Double?
    /// Watts the Mac is using.
    public var systemWatts: Double?
    /// Magnitude of battery power in watts.
    public var batteryWatts: Double?
    public var batteryDirection: BatteryDirection
    /// Watts lost as heat converting the charger's voltage.
    public var adapterLossWatts: Double?

    /// Below this, battery flow is treated as idle (sensor noise).
    static let idleThreshold = 0.25

    public init(adapterWatts: Double?, systemWatts: Double?, batteryWatts: Double?,
                batteryDirection: BatteryDirection, adapterLossWatts: Double? = nil) {
        self.adapterWatts = adapterWatts
        self.systemWatts = systemWatts
        self.batteryWatts = batteryWatts
        self.batteryDirection = batteryDirection
        self.adapterLossWatts = adapterLossWatts
    }

    /// Derives the flow from a snapshot. Uses PowerTelemetryData when
    /// present; otherwise estimates from battery volts × amps, which is enough
    /// for the on-battery case (system load ≈ battery output).
    public init(snapshot: BatterySnapshot) {
        let telemetry = snapshot.telemetry
        var battery = snapshot.batteryWatts

        // The amperage sign is the most reliable charging indicator; if the
        // telemetry disagrees, follow the amperage.
        if let watts = battery, let amperage = snapshot.amperage, amperage != 0,
           (watts > 0) != (amperage > 0) {
            battery = -watts
        }

        let signedBattery = battery ?? 0
        if abs(signedBattery) < Self.idleThreshold {
            batteryDirection = .idle
        } else {
            batteryDirection = signedBattery > 0 ? .charging : .discharging
        }
        batteryWatts = battery.map(abs)

        if snapshot.isPluggedIn {
            adapterWatts = telemetry?.systemPowerIn.map { Double($0) / 1000 }
        } else {
            adapterWatts = nil
        }

        if let load = telemetry?.systemLoad, load > 0 {
            systemWatts = Double(load) / 1000
        } else if let adapter = adapterWatts {
            systemWatts = max(0, adapter - signedBattery)
        } else if !snapshot.isPluggedIn, battery != nil {
            systemWatts = max(0, -signedBattery)
        } else {
            systemWatts = nil
        }

        adapterLossWatts = snapshot.isPluggedIn
            ? telemetry?.adapterEfficiencyLoss.flatMap { $0 > 0 ? Double($0) / 1000 : nil }
            : nil
    }
}
