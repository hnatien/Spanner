import Foundation

/// Typed reads from an IOKit property dictionary (CF types bridged to
/// Foundation). Keeps parsing independent of IOKit so tests can pass plain
/// Swift dictionaries shaped like `ioreg` output.
public struct PropertyBag {
    public let values: [String: Any]

    public init(_ values: [String: Any]) {
        self.values = values
    }

    /// Integer value. Reads through `int64Value` so registry values that are
    /// really signed (InstantAmperage, BatteryPower) but stored as unsigned
    /// 64-bit come back negative instead of as 18446744073709550456.
    public func int(_ key: String) -> Int? {
        switch values[key] {
        case let number as NSNumber: Int(truncatingIfNeeded: number.int64Value)
        case let value as Int: value
        case let value as UInt64: Int(truncatingIfNeeded: Int64(bitPattern: value))
        default: nil
        }
    }

    public func double(_ key: String) -> Double? {
        (values[key] as? NSNumber)?.doubleValue
    }

    /// Boolean value; registry flags appear both as booleans and as 0/1.
    public func bool(_ key: String) -> Bool? {
        switch values[key] {
        case let value as Bool: value
        case let number as NSNumber: number.boolValue
        default: nil
        }
    }

    public func string(_ key: String) -> String? {
        values[key] as? String
    }

    public func bag(_ key: String) -> PropertyBag? {
        (values[key] as? [String: Any]).map(PropertyBag.init)
    }

    public func bags(_ key: String) -> [PropertyBag] {
        (values[key] as? [[String: Any]])?.map(PropertyBag.init) ?? []
    }
}
