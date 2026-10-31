// Spike (d): does disabling the system Cmd+Tab symbolic hotkey still let a
// Carbon hotkey receive Cmd+Tab on this macOS build? Mirrors AltTab's approach
// (CGSSymbolicHotKey.swift + KeyboardEvents.swift).
//
//   hotkey-spike status              print current symbolic hotkey state
//   hotkey-spike restore             re-enable Cmd+Tab / Cmd+Shift+Tab
//   hotkey-spike manual [seconds]    disable, listen for real presses, restore
//   hotkey-spike self-test           post synthetic Cmd+Tab with and without
//                                    the system hotkey (needs PostEvent access)

import AppKit
import Carbon.HIToolbox

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

let commandTab: Int32 = 1
let commandShiftTab: Int32 = 2
let start = Date()
var hits = 0

// The disable persists after the process exits, so every exit path restores
// whatever state we found.
let originalCommandTab = CGSIsSymbolicHotKeyEnabled(commandTab)
let originalCommandShiftTab = CGSIsSymbolicHotKeyEnabled(commandShiftTab)

func log(_ message: String) {
    print(String(format: "[%6.2fs] ", Date().timeIntervalSince(start)) + message)
    fflush(stdout)
}

func states() -> String {
    "cmdTab=\(CGSIsSymbolicHotKeyEnabled(commandTab)) cmdShiftTab=\(CGSIsSymbolicHotKeyEnabled(commandShiftTab))"
}

func restore() {
    CGSSetSymbolicHotKeyEnabled(commandTab, originalCommandTab)
    CGSSetSymbolicHotKeyEnabled(commandShiftTab, originalCommandShiftTab)
}

func disableSystemSwitcher() {
    let a = CGSSetSymbolicHotKeyEnabled(commandTab, false)
    let b = CGSSetSymbolicHotKeyEnabled(commandShiftTab, false)
    log("disable returned \(a.rawValue)/\(b.rawValue); now \(states())")
}

func finish(_ code: Int32) -> Never {
    restore()
    log("restored; now \(states())")
    exit(code)
}

func registerCarbonCommandTab() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
        hits += 1
        log("Carbon Cmd+Tab hotkey fired (#\(hits))")
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x5350_4E52), id: 1)
    let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(cmdKey), id, GetEventDispatcherTarget(), 0, &ref)
    log("RegisterEventHotKey(Cmd+Tab) status=\(status)")
    if status != noErr { finish(1) }
}

func postCommandTab() {
    let source = CGEventSource(stateID: .hidSystemState)
    let steps: [(CGKeyCode, Bool)] = [(CGKeyCode(kVK_Command), true), (CGKeyCode(kVK_Tab), true),
                                      (CGKeyCode(kVK_Tab), false), (CGKeyCode(kVK_Command), false)]
    for (key, down) in steps {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
        event.flags = (key == CGKeyCode(kVK_Command) && !down) ? [] : .maskCommand
        event.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig) { _ in restore(); exit(130) }
}

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "status"
log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString); initial \(states())")

switch command {
case "status":
    exit(0)
case "restore":
    CGSSetSymbolicHotKeyEnabled(commandTab, true)
    CGSSetSymbolicHotKeyEnabled(commandShiftTab, true)
    log("forced enable; now \(states())")
    exit(0)
case "manual":
    let seconds = args.dropFirst().first.flatMap(Double.init) ?? 20
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    registerCarbonCommandTab()
    disableSystemSwitcher()
    log("press Cmd+Tab a few times now; the system switcher should NOT appear (\(Int(seconds))s)")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        log(hits > 0 ? "RESULT: override works (\(hits) presses captured)" : "RESULT: no presses captured")
        finish(hits > 0 ? 0 : 3)
    }
    NSApp.run()
case "self-test":
    guard CGPreflightPostEventAccess() else {
        log("no PostEvent access for this process; use `manual` instead")
        exit(2)
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    registerCarbonCommandTab()
    log("phase A: system hotkey enabled, posting Cmd+Tab")
    postCommandTab()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let hitsWhileEnabled = hits
        disableSystemSwitcher()
        log("phase B: system hotkey disabled, posting Cmd+Tab")
        postCommandTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let hitsWhileDisabled = hits - hitsWhileEnabled
            log("RESULT: hits while enabled=\(hitsWhileEnabled), while disabled=\(hitsWhileDisabled)")
            finish(hitsWhileDisabled > 0 ? 0 : 3)
        }
    }
    NSApp.run()
default:
    log("unknown command \(command)")
    exit(64)
}
