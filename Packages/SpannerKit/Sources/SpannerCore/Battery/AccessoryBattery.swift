import Foundation

/// Battery of a connected Apple accessory (Magic Keyboard, Mouse, Trackpad),
/// read from IORegistry services that publish a `BatteryPercent` property.
public struct AccessoryBattery: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case keyboard, mouse, trackpad, other
    }

    public let id: String
    public let name: String
    public let percent: Int
    public let kind: Kind

    public init(id: String, name: String, percent: Int) {
        self.id = id
        self.name = name
        self.percent = min(100, max(0, percent))
        let lowered = name.lowercased()
        kind = lowered.contains("keyboard") ? .keyboard
            : lowered.contains("trackpad") ? .trackpad
            : lowered.contains("mouse") ? .mouse
            : .other
    }

    /// Parses one registry service; nil when it has no battery level.
    public init?(id: String, properties: PropertyBag) {
        guard let percent = properties.int("BatteryPercent") else { return nil }
        let name = properties.string("Product") ?? properties.string("DeviceName") ?? "Accessory"
        self.init(id: id, name: name, percent: percent)
    }

    public var level: ChargeLevel { ChargeLevel(percent: percent) }
}
