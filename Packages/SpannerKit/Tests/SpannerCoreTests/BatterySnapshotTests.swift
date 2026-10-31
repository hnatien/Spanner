import Foundation
import Testing
@testable import SpannerCore

/// Fixtures mirror `ioreg -rn AppleSmartBattery` on a MacBook Air M4,
/// macOS 27.2 (Phase 0).
enum BatteryFixtures {
    static var charging: [String: Any] {
        [
            "BatteryInstalled": true,
            "CurrentCapacity": 82,
            "IsCharging": true,
            "ExternalConnected": true,
            "FullyCharged": false,
            // macOS 27 nests capacities under BatteryData.
            "BatteryData": [
                "AppleRawMaxCapacity": 4375,
                "DesignCapacity": 4629,
                "NominalChargeCapacity": 4502,
                "AppleRawCurrentCapacity": 3544,
            ] as [String: Any],
            "CycleCount": 63,
            "DesignCycleCount9C": 1000,
            "Voltage": 12879,
            "InstantAmperage": 1175,
            "AvgTimeToFull": 92,
            "AvgTimeToEmpty": 65535,
            "ChargerData": ["IsCharging": 1, "NotChargingReason": 0] as [String: Any],
            "AdapterDetails": [
                "Watts": 34,
                "Description": "pd charger",
                "AdapterVoltage": 20000,
                "Current": 1700,
                "IsWireless": false,
                "UsbHvcHvcIndex": 4,
                "UsbHvcMenu": [
                    ["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
                    ["Index": 1, "MaxCurrent": 3000, "MaxVoltage": 9000],
                    ["Index": 2, "MaxCurrent": 2830, "MaxVoltage": 12000],
                    ["Index": 3, "MaxCurrent": 2260, "MaxVoltage": 15000],
                    ["Index": 4, "MaxCurrent": 1700, "MaxVoltage": 20000],
                ] as [[String: Any]],
            ] as [String: Any],
            "PowerTelemetryData": [
                "SystemPowerIn": 31640,
                "SystemLoad": 16092,
                "BatteryPower": 15548,
                "AdapterEfficiencyLoss": 815,
            ] as [String: Any],
        ]
    }

    /// Unplugged: ioreg prints the negative current as an unsigned wrap.
    static var onBattery: [String: Any] {
        var values = charging
        values["IsCharging"] = false
        values["ExternalConnected"] = false
        values["InstantAmperage"] = UInt64(18446744073709550456)  // −1160 mA
        values["AvgTimeToFull"] = 65535
        values["AvgTimeToEmpty"] = 190
        values["AdapterDetails"] = [String: Any]()
        values["PowerTelemetryData"] = [
            "SystemPowerIn": 0,
            "SystemLoad": 14_900,
            "BatteryPower": UInt64(bitPattern: -14_900),
            "AdapterEfficiencyLoss": 0,
        ] as [String: Any]
        return values
    }

    /// Charger connected but charging cut off, as in the Phase 0 CHIE test.
    static var pluggedNotCharging: [String: Any] {
        var values = charging
        values["IsCharging"] = false
        values["InstantAmperage"] = UInt64(18446744073709550456)
        values["ChargerData"] = ["IsCharging": 0, "NotChargingReason": 0x1000] as [String: Any]
        return values
    }
}

@Suite("Battery snapshot parsing")
struct BatterySnapshotTests {
    @Test func parsesChargingSnapshot() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.charging)))
        #expect(snapshot.percent == 82)
        #expect(snapshot.state == .charging)
        #expect(snapshot.cycleCount == 63)
        #expect(snapshot.designCycleCount == 1000)
        #expect(snapshot.maxCapacity == 4375)
        #expect(snapshot.designCapacity == 4629)
        #expect(snapshot.currentCapacity == 3544)
        #expect(snapshot.voltage == 12879)
        #expect(snapshot.amperage == 1175)
        #expect(snapshot.minutesToFull == 92)
        #expect(snapshot.minutesToEmpty == nil)
        #expect(snapshot.statusText == "Charging · 1 h 32 min to full")
    }

    @Test func readsUnsignedWrappedAmperageAsNegative() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.onBattery)))
        #expect(snapshot.amperage == -1160)
        #expect(snapshot.state == .discharging)
        #expect(snapshot.charger == nil)
        #expect(snapshot.statusText == "On battery · 3 h 10 min left")
    }

    @Test func treats65535AndNegativeMinutesAsUnknown() {
        #expect(BatterySnapshot.minutes(65535) == nil)
        #expect(BatterySnapshot.minutes(-1) == nil)
        #expect(BatterySnapshot.minutes(0) == nil)
        #expect(BatterySnapshot.minutes(nil) == nil)
        #expect(BatterySnapshot.minutes(42) == 42)
    }

    @Test func prefersPowerSourceTimeEstimates() throws {
        let powerSource = PropertyBag(["Time to Full Charge": 75, "Optimized Battery Charging Engaged": 1])
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.charging), powerSource: powerSource))
        #expect(snapshot.minutesToFull == 75)
        #expect(snapshot.optimizedChargingEngaged)
    }

    @Test func missingKeysStayNil() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(["CurrentCapacity": 50])))
        #expect(snapshot.percent == 50)
        #expect(snapshot.state == .discharging)
        #expect(snapshot.health == nil)
        #expect(snapshot.cycleCount == nil)
        #expect(snapshot.charger == nil)
        #expect(snapshot.telemetry == nil)
        #expect(snapshot.batteryWatts == nil)
    }

    @Test func noBatteryInstalledYieldsNil() {
        #expect(BatterySnapshot(registry: PropertyBag(["BatteryInstalled": false, "CurrentCapacity": 0])) == nil)
        #expect(BatterySnapshot(registry: PropertyBag([:])) == nil)
    }

    @Test func clampsPercent() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(["CurrentCapacity": 140])))
        #expect(snapshot.percent == 100)
    }

    @Test func healthIsRawMaxOverDesign() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.charging)))
        let health = try #require(snapshot.health)
        #expect(abs(health - 4375.0 / 4629.0) < 0.0001)
        #expect(snapshot.cycleFraction == 0.063)
    }

    @Test func readsTopLevelCapacitiesFromOlderMacOS() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(["CurrentCapacity": 50, "AppleRawMaxCapacity": 4000, "DesignCapacity": 5000])))
        #expect(snapshot.health == 0.8)
    }

    @Test func healthNeedsNonZeroDesignCapacity() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(["CurrentCapacity": 50, "AppleRawMaxCapacity": 4000, "DesignCapacity": 0])))
        #expect(snapshot.health == nil)
    }

    @Test func levelBands() {
        #expect(ChargeLevel(percent: 5) == .critical)
        #expect(ChargeLevel(percent: 10) == .low)
        #expect(ChargeLevel(percent: 19) == .low)
        #expect(ChargeLevel(percent: 20) == .normal)
    }

    @Test func pluggedNotChargingExplainsReason() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.pluggedNotCharging)))
        #expect(snapshot.state == .pluggedNotCharging)
        #expect(snapshot.notChargingReason == 0x1000)
        #expect(snapshot.statusText == "Plugged in, not charging")
        #expect(snapshot.notChargingExplanation?.contains("turned off by software") == true)
    }

    @Test func unknownReasonShowsRawCode() {
        #expect(BatterySnapshot.explanation(forNotChargingReason: 0x24).contains("0x24"))
    }

    @Test func optimizedChargingExplanationWhenNoReason() throws {
        var values = BatteryFixtures.charging
        values["IsCharging"] = false
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(values),
                                                    powerSource: PropertyBag(["Optimized Battery Charging Engaged": true])))
        #expect(snapshot.notChargingExplanation?.contains("Optimized Charging") == true)
    }

    @Test func fullWhenPluggedAtHundred() throws {
        var values = BatteryFixtures.charging
        values["IsCharging"] = false
        values["CurrentCapacity"] = 100
        values["FullyCharged"] = true
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(values)))
        #expect(snapshot.state == .full)
        #expect(snapshot.notChargingExplanation == nil)
    }
}

@Suite("Charger")
struct ChargerTests {
    @Test func parsesPDProfilesAndActiveIndex() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.charging)))
        let charger = try #require(snapshot.charger)
        #expect(charger.profiles.count == 5)
        #expect(charger.activeProfile == PDProfile(index: 4, voltage: 20000, current: 1700))
        #expect(charger.activeProfile?.watts == 34)
        #expect(charger.displayName == "34 W USB-C")
        #expect(charger.negotiatedText == "20 V × 1.70 A")
    }

    @Test func emptyAdapterDetailsIsNoCharger() {
        #expect(ChargerInfo(adapterDetails: PropertyBag([:])) == nil)
        #expect(ChargerInfo(adapterDetails: PropertyBag(["Watts": 0])) == nil)
    }

    @Test func nonPDChargerName() throws {
        let charger = try #require(ChargerInfo(adapterDetails: PropertyBag(["Watts": 60, "Description": "magsafe"])))
        #expect(charger.displayName == "60 W Charger")
        #expect(charger.activeProfile == nil)
    }
}

@Suite("Power flow")
struct PowerFlowTests {
    @Test func chargingFlowUsesTelemetry() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.charging)))
        let flow = PowerFlow(snapshot: snapshot)
        #expect(flow.adapterWatts == 31.64)
        #expect(flow.systemWatts == 16.092)
        #expect(flow.batteryWatts == 15.548)
        #expect(flow.batteryDirection == .charging)
        #expect(flow.adapterLossWatts == 0.815)
    }

    @Test func onBatteryFlowsFromBattery() throws {
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(BatteryFixtures.onBattery)))
        let flow = PowerFlow(snapshot: snapshot)
        #expect(flow.adapterWatts == nil)
        #expect(flow.batteryDirection == .discharging)
        #expect(flow.batteryWatts == 14.9)
        #expect(flow.systemWatts == 14.9)
        #expect(flow.adapterLossWatts == nil)
    }

    @Test func onBatteryWithoutTelemetryEstimatesFromVoltsTimesAmps() throws {
        var values = BatteryFixtures.onBattery
        values["PowerTelemetryData"] = nil
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(values)))
        let flow = PowerFlow(snapshot: snapshot)
        let expected = 12.879 * 1.160
        #expect(abs((flow.batteryWatts ?? 0) - expected) < 0.001)
        #expect(abs((flow.systemWatts ?? 0) - expected) < 0.001)
        #expect(flow.batteryDirection == .discharging)
    }

    @Test func amperageSignWinsOverDisagreeingTelemetry() throws {
        var values = BatteryFixtures.pluggedNotCharging
        values["PowerTelemetryData"] = ["SystemPowerIn": 0, "SystemLoad": 12_000, "BatteryPower": 12_000] as [String: Any]
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(values)))
        let flow = PowerFlow(snapshot: snapshot)
        #expect(flow.batteryDirection == .discharging)
        #expect(flow.systemWatts == 12)
    }

    @Test func tinyBatteryPowerIsIdle() throws {
        var values = BatteryFixtures.charging
        values["IsCharging"] = false
        values["InstantAmperage"] = 0
        values["PowerTelemetryData"] = ["SystemPowerIn": 9_000, "SystemLoad": 8_900, "BatteryPower": 100] as [String: Any]
        let snapshot = try #require(BatterySnapshot(registry: PropertyBag(values)))
        let flow = PowerFlow(snapshot: snapshot)
        #expect(flow.batteryDirection == .idle)
        #expect(flow.adapterWatts == 9)
    }
}

@Suite("Battery formatting")
struct BatteryFormatTests {
    @Test func units() {
        #expect(BatteryFormat.watts(15.548) == "15.5 W")
        #expect(BatteryFormat.watts(140.2) == "140 W")
        #expect(BatteryFormat.volts(12879) == "12.88 V")
        #expect(BatteryFormat.volts(20000, digits: 0) == "20 V")
        #expect(BatteryFormat.amps(1175, signed: true) == "+1.18 A")
        #expect(BatteryFormat.amps(-1160, signed: true) == "−1.16 A")
        #expect(BatteryFormat.celsius(35.62) == "35.6 °C")
    }
}

@Suite("Accessory battery")
struct AccessoryBatteryTests {
    @Test func parsesKindFromProductName() throws {
        let keyboard = try #require(AccessoryBattery(id: "1", properties: PropertyBag(["BatteryPercent": 64, "Product": "Magic Keyboard with Touch ID"])))
        #expect(keyboard.kind == .keyboard)
        #expect(keyboard.percent == 64)
        #expect(AccessoryBattery(id: "2", name: "Magic Trackpad", percent: 120).percent == 100)
        #expect(AccessoryBattery(id: "3", name: "Magic Mouse", percent: 5).level == .critical)
    }

    @Test func serviceWithoutPercentIsIgnored() {
        #expect(AccessoryBattery(id: "1", properties: PropertyBag(["Product": "Magic Mouse"])) == nil)
    }
}
