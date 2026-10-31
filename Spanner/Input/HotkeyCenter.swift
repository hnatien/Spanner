import Carbon.HIToolbox
import Foundation
import SpannerCore

/// Global shortcuts through Carbon `RegisterEventHotKey`. Needs no permission
/// and is matched before the frontmost app sees the key. Held keys repeat,
/// so a held Tab keeps firing (Phase 0 measured ~160 ms per repeat).
///
/// One instance serves every module (`AppModel.hotkeys`): hotkey IDs are
/// only unique within a center, so two centers would dispatch each other's
/// shortcuts.
final class HotkeyCenter {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var combinations: [UInt32: (keyCode: UInt32, modifiers: UInt32)] = [:]
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

    /// Set while a shortcut recorder is listening. Carbon hotkeys are matched
    /// before any window sees the key, so they are released for the duration;
    /// otherwise pressing a combination Spanner already uses would fire it
    /// instead of reaching the recorder.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            if isSuspended {
                references.values.forEach { UnregisterEventHotKey($0) }
                references = [:]
            } else {
                for (id, combination) in combinations {
                    references[id] = Self.install(id: id, keyCode: combination.keyCode, modifiers: combination.modifiers)
                }
            }
        }
    }

    /// Registers a shortcut. Returns nil if the combination is taken.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> UInt32? {
        let id = nextID
        nextID += 1
        if !isSuspended {
            guard let reference = Self.install(id: id, keyCode: keyCode, modifiers: modifiers) else { return nil }
            references[id] = reference
        }
        combinations[id] = (keyCode, modifiers)
        handlers[id] = handler
        return id
    }

    private static func install(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetEventDispatcherTarget(), 0, &reference)
        return status == noErr ? reference : nil
    }

    @discardableResult
    func register(_ shortcut: KeyShortcut, handler: @escaping Handler) -> UInt32? {
        register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, handler: handler)
    }

    func unregister(_ ids: [UInt32]) {
        for id in ids {
            if let reference = references.removeValue(forKey: id) {
                UnregisterEventHotKey(reference)
            }
            combinations[id] = nil
            handlers[id] = nil
        }
    }

    private func dispatch(_ id: UInt32) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler()
        return true
    }
}
