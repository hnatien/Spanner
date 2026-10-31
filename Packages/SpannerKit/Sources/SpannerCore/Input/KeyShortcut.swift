import Foundation

/// A global keyboard shortcut: a virtual key code plus Carbon modifiers, as
/// `RegisterEventHotKey` takes them. Stored in UserDefaults as JSON.
public struct KeyShortcut: Hashable, Sendable, Codable {
    public let keyCode: UInt32
    /// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon modifier bits, mirrored from HIToolbox.
    public enum Modifier {
        public static let command: UInt32 = 0x0100
        public static let shift: UInt32 = 0x0200
        public static let option: UInt32 = 0x0800
        public static let control: UInt32 = 0x1000
        public static let all: UInt32 = command | shift | option | control
    }

    /// A shortcut must hold at least one modifier other than Shift alone,
    /// otherwise it would swallow ordinary typing. Function keys are exempt.
    public var isValid: Bool {
        if Self.functionKeys[keyCode] != nil { return true }
        return modifiers & (Modifier.command | Modifier.option | Modifier.control) != 0
    }

    /// Keycaps in macOS order: ⌃ ⌥ ⇧ ⌘ then the key.
    public var keycaps: [String] {
        var caps: [String] = []
        if modifiers & Modifier.control != 0 { caps.append("⌃") }
        if modifiers & Modifier.option != 0 { caps.append("⌥") }
        if modifiers & Modifier.shift != 0 { caps.append("⇧") }
        if modifiers & Modifier.command != 0 { caps.append("⌘") }
        caps.append(Self.keyName(keyCode))
        return caps
    }

    public var displayString: String { keycaps.joined() }

    /// Converts AppKit's `NSEvent.ModifierFlags` raw value to Carbon bits.
    public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if flags & (1 << 20) != 0 { result |= Modifier.command }
        if flags & (1 << 17) != 0 { result |= Modifier.shift }
        if flags & (1 << 19) != 0 { result |= Modifier.option }
        if flags & (1 << 18) != 0 { result |= Modifier.control }
        return result
    }

    static let functionKeys: [UInt32: String] = [
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19",
    ]

    /// Names for keys on an ANSI layout. Letters follow the physical key,
    /// which matches how `RegisterEventHotKey` matches them.
    static let keyNames: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x29: ";", 0x27: "'", 0x2A: "\\", 0x2B: ",",
        0x2F: ".", 0x2C: "/", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x75: "⌦", 0x35: "⎋",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
    ]

    public static func keyName(_ keyCode: UInt32) -> String {
        keyNames[keyCode] ?? functionKeys[keyCode] ?? "Key \(keyCode)"
    }
}
