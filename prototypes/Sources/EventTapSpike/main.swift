// Spike (c): does a listen-only session event tap (AltTab's modifier-release
// detector) need Input Monitoring? Run it as its own .app (see bundle.sh) so
// TCC attributes the request to this bundle, not to the launching terminal.
//
//   eventtap-spike --mode flags|keys [--seconds N] [--log PATH] [--request-ax]
//
// "flags" listens to flagsChanged only (what a switcher needs); "keys" also
// listens to keyDown/keyUp. Press modifiers and type during the run.

import AppKit
import ApplicationServices

var options: [String: String] = [:]
var flags: Set<String> = []
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iterator.next() {
    if arg == "--request-ax" { flags.insert(arg) } else if let value = iterator.next() { options[arg] = value }
}

let mode = options["--mode"] ?? "flags"
let seconds = options["--seconds"].flatMap(Double.init) ?? 15
let logURL = URL(fileURLWithPath: options["--log"] ?? NSTemporaryDirectory() + "eventtap-spike.log")
let start = Date()

func log(_ message: String) {
    let line = String(format: "[%6.2fs] ", Date().timeIntervalSince(start)) + message + "\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

func access() -> String {
    "listenEvent=\(CGPreflightListenEventAccess()) postEvent=\(CGPreflightPostEventAccess()) ax=\(AXIsProcessTrusted())"
}

var counts: [String: Int] = [:]

log("mode=\(mode) seconds=\(Int(seconds)) bundle=\(Bundle.main.bundleIdentifier ?? "none")")
log("before: \(access())")

if flags.contains("--request-ax") {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    log("AXIsProcessTrustedWithOptions(prompt) -> \(AXIsProcessTrustedWithOptions(prompt))")
}

var mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
if mode == "keys" {
    mask |= CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
}

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, _ in
        let name: String
        switch type {
        case .flagsChanged: name = "flagsChanged"
        case .keyDown: name = "keyDown"
        case .keyUp: name = "keyUp"
        case .tapDisabledByTimeout: name = "tapDisabledByTimeout"
        case .tapDisabledByUserInput: name = "tapDisabledByUserInput"
        default: name = "type\(type.rawValue)"
        }
        counts[name, default: 0] += 1
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
)

log("tapCreate -> \(tap == nil ? "nil (refused)" : "created")")
log("after tapCreate: \(access())")

if let tap {
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("press Cmd/Option/Shift and type a few letters now")
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    let summary = counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    log("events received: \(summary)")
    log("end: \(access())")
    exit(0)
}
NSApp.run()
