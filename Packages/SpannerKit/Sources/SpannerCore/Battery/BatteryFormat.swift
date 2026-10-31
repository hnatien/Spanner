import Foundation

/// Unit formatting for electrical values, so every battery surface shows
/// the same precision.
public enum BatteryFormat {
    /// "15.5 W"; whole watts from 100 W up.
    public static func watts(_ watts: Double) -> String {
        watts >= 100 ? String(format: "%.0f W", watts) : String(format: "%.1f W", watts)
    }

    /// Millivolts as volts: "12.88 V" (or "20 V" with digits: 0).
    public static func volts(_ millivolts: Int, digits: Int = 2) -> String {
        String(format: "%.\(digits)f V", Double(millivolts) / 1000)
    }

    /// Milliamps as amps with an explicit sign when asked: "+1.18 A".
    public static func amps(_ milliamps: Int, signed: Bool = false) -> String {
        let value = Double(milliamps) / 1000
        if signed && value > 0 { return String(format: "+%.2f A", value) }
        if value < 0 { return String(format: "−%.2f A", -value) }
        return String(format: "%.2f A", value)
    }

    /// "4,375 mAh".
    public static func milliampHours(_ value: Int) -> String {
        "\(value.formatted(.number.grouping(.automatic))) mAh"
    }

    /// "35.6 °C".
    public static func celsius(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }
}
