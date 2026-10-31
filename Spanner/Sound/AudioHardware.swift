import CoreAudio
import Foundation

/// An audio device as the Sound page and menu show it.
struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
    let transportType: UInt32

    /// HDMI and DisplayPort outputs are usually a monitor's speakers, whose
    /// volume macOS can't set; DDC can (see DisplayController).
    var isDisplayAudio: Bool {
        transportType == kAudioDeviceTransportTypeHDMI || transportType == kAudioDeviceTransportTypeDisplayPort
    }

    var symbol: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: hasOutput ? "laptopcomputer" : "mic.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "display"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        default: hasOutput ? "hifispeaker.fill" : "mic.fill"
        }
    }
}

/// Thin typed wrappers over the Core Audio property API.
enum AudioHardware {
    /// UID prefix of Spanner's private aggregate devices, which are hidden
    /// from the device lists.
    static let ownDevicePrefix = "dev.spanner.volume."

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as _: T.Type) -> T? {
        var address = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    static func getArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, of _: T.Type) -> [T] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func getString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, to value: T) -> Bool {
        var address = address(selector, scope: scope)
        var value = value
        return withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer)
        } == noErr
    }

    static func isSettable(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    // MARK: - Devices

    static func devices() -> [AudioDevice] {
        getArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, of: AudioObjectID.self)
            .compactMap(device)
            .filter { !$0.uid.hasPrefix(ownDevicePrefix) }
    }

    static func device(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = getString(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = getString(id, kAudioObjectPropertyName) ?? uid
        return AudioDevice(id: id, uid: uid, name: name,
                           hasOutput: channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                           hasInput: channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
                           transportType: get(id, kAudioDevicePropertyTransportType, as: UInt32.self) ?? 0)
    }

    static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let id = get(AudioObjectID(kAudioObjectSystemObject), selector, as: AudioObjectID.self)
        return id == kAudioObjectUnknown ? nil : id
    }

    /// Makes `id` the default device. For output, alert sounds follow when
    /// they were going to the previous default, as Control Center does.
    static func setDefaultDevice(_ id: AudioObjectID, input: Bool) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if input {
            set(system, kAudioHardwarePropertyDefaultInputDevice, to: id)
            return
        }
        let previous = defaultDevice(input: false)
        let alerts = get(system, kAudioHardwarePropertyDefaultSystemOutputDevice, as: AudioObjectID.self)
        set(system, kAudioHardwarePropertyDefaultOutputDevice, to: id)
        if alerts == previous {
            set(system, kAudioHardwarePropertyDefaultSystemOutputDevice, to: id)
        }
    }

    // MARK: - Processes

    /// One process that has registered with the audio system.
    struct AudioProcess {
        let object: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let isPlaying: Bool
    }

    static func processes() -> [AudioProcess] {
        getArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
            .compactMap { object in
                guard let pid = get(object, kAudioProcessPropertyPID, as: pid_t.self) else { return nil }
                let bundleID = getString(object, kAudioProcessPropertyBundleID).flatMap { $0.isEmpty ? nil : $0 }
                let playing = (get(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0) != 0
                return AudioProcess(object: object, pid: pid, bundleID: bundleID, isPlaying: playing)
            }
    }
}
