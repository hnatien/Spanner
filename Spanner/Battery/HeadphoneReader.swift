import Foundation
import IOBluetooth
import SpannerCore

/// Reads headphone battery and ear status from IOBluetooth.
///
/// Neither is public API. The values come from private `IOBluetoothDevice`
/// getters (present on macOS 27.2): `batteryPercentLeft/Right/Case/Single`
/// return a UInt8 where 0 means unknown, and `isInEarDetectionSupported`,
/// `inEarDetect` (Automatic Ear Detection on) and `inEar` return BOOL. Each
/// is checked with `responds(to:)` first, so if Apple removes one the value
/// reads as unknown instead of crashing. Needs the Bluetooth permission.
enum HeadphoneReader {
    /// Connected audio devices that report a battery level.
    static func connected() -> [HeadphoneBattery] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return devices.compactMap { device in
            guard device.isConnected(),
                  device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio),
                  let address = device.addressString else { return nil }
            let earDetection = bool(device, "isInEarDetectionSupported") == true && bool(device, "inEarDetect") == true
            let headphone = HeadphoneBattery(id: address, name: device.name ?? "Headphones",
                                             left: level(device, "batteryPercentLeft"),
                                             right: level(device, "batteryPercentRight"),
                                             chargingCase: level(device, "batteryPercentCase"),
                                             single: level(device, "batteryPercentSingle"),
                                             isInEar: earDetection ? bool(device, "inEar") : nil)
            return headphone.hasBattery ? headphone : nil
        }
        .sorted { $0.name < $1.name }
    }

    private static func level(_ device: IOBluetoothDevice, _ name: String) -> Int {
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector) else { return 0 }
        return Int(unsafeBitCast(device.method(for: selector), to: Getter.self)(device, selector))
    }

    private static func bool(_ device: IOBluetoothDevice, _ name: String) -> Bool? {
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector) else { return nil }
        return unsafeBitCast(device.method(for: selector), to: Getter.self)(device, selector)
    }
}
