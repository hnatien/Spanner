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

    /// "4,375 mAh". Grouped with a comma whatever the region, because the
    /// other units here always use "." as the decimal point; a locale "."
    /// separator would make 2.975 mAh read as two and a bit.
    public static func milliampHours(_ value: Int) -> String {
        "\(value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))) mAh"
    }

    /// A time estimate rounded to what it can really promise: nearest
    /// 5 minutes under an hour, nearest 15 from an hour up ("4 h", "1 h 15 min").
    public static func roughDuration(minutes: Int) -> String {
        let step = minutes < 60 ? 5 : 15
        let rounded = minutes < step ? minutes
            : Int((Double(minutes) / Double(step)).rounded()) * step
        return SpannerFormat.duration(Double(rounded) * 60)
    }

    /// "35.6 °C".
    public static func celsius(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }
}
