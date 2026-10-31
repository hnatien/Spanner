import Foundation

/// The modifier the person holds to switch windows. Tab cycles all windows;
/// the grave key (`) cycles windows of the frontmost app.
public enum SwitcherTrigger: String, CaseIterable, Identifiable, Sendable, Codable {
    case option
    case control
    case command

    public var id: Self { self }

    public var title: String {
        switch self {
        case .option: "Option-Tab"
        case .control: "Control-Tab"
        case .command: "Command-Tab"
        }
    }

    public var modifierSymbol: String {
        switch self {
        case .option: "⌥"
        case .control: "⌃"
        case .command: "⌘"
        }
    }

    /// Carbon modifier mask for `RegisterEventHotKey` (optionKey, controlKey, cmdKey).
    public var carbonModifier: UInt32 {
        switch self {
        case .option: 0x0800
        case .control: 0x1000
        case .command: 0x0100
        }
    }

    /// CGEventFlags raw mask used to notice when the modifier is released
    /// (maskAlternate, maskControl, maskCommand).
    public var eventFlagMask: UInt64 {
        switch self {
        case .option: 0x0008_0000
        case .control: 0x0004_0000
        case .command: 0x0010_0000
        }
    }

    /// Command-Tab belongs to the macOS app switcher, so using it means
    /// switching the system shortcut off while Spanner runs.
    public var replacesSystemSwitcher: Bool { self == .command }

    public var keycaps: [String] { [modifierSymbol, "⇥"] }
    public var appWindowsKeycaps: [String] { [modifierSymbol, "`"] }
}

/// Virtual key codes and modifier masks from Carbon's HIToolbox, mirrored
/// here so the pure logic doesn't import Carbon.
public enum CarbonKey {
    public static let tab: UInt32 = 0x30
    public static let grave: UInt32 = 0x32
    public static let escape: UInt32 = 0x35
    public static let returnKey: UInt32 = 0x24
    public static let leftArrow: UInt32 = 0x7B
    public static let rightArrow: UInt32 = 0x7C
    public static let downArrow: UInt32 = 0x7D
    public static let upArrow: UInt32 = 0x7E
    public static let shiftModifier: UInt32 = 0x0200
}

public enum ThumbnailSize: String, CaseIterable, Identifiable, Sendable, Codable {
    case small, medium, large

    public var id: Self { self }

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Width of a thumbnail in points; height follows a 16:10 frame.
    public var tileWidth: Double {
        switch self {
        case .small: 160
        case .medium: 220
        case .large: 300
        }
    }
}

public enum OverlayScreen: String, CaseIterable, Identifiable, Sendable, Codable {
    case pointer, main

    public var id: Self { self }

    public var title: String {
        switch self {
        case .pointer: "Screen with pointer"
        case .main: "Main screen"
        }
    }
}
