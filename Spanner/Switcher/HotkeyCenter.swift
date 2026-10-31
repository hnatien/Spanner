import Carbon.HIToolbox
import Foundation

/// Global shortcuts through Carbon `RegisterEventHotKey`. Needs no permission
/// and is matched before the frontmost app sees the key. Held keys repeat,
/// so a held Tab keeps firing (Phase 0 measured ~160 ms per repeat).
final class HotkeyCenter {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature = OSType(0x5350_4E52) // "SPNR"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // The dispatcher target delivers on the main thread.
            return MainActor.assumeIsolated { center.dispatch(hotKeyID.id) ? noErr : OSStatus(eventNotHandledErr) }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Registers a shortcut. Returns nil if the combination is taken.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> UInt32? {
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        references[id] = reference
        handlers[id] = handler
        return id
    }

    func unregister(_ ids: [UInt32]) {
        for id in ids {
            if let reference = references.removeValue(forKey: id) {
                UnregisterEventHotKey(reference)
            }
            handlers[id] = nil
        }
    }

    private func dispatch(_ id: UInt32) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler()
        return true
    }
}
