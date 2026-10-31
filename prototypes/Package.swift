// swift-tools-version:5.9
import PackageDescription

// Phase 0 spikes: throwaway probes that answer the open questions in
// docs/macOS utilities app feasibility.md before committing to the MVP.
let package = Package(
    name: "Phase0",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "hotkey-spike", path: "Sources/HotkeySpike"),
        .executableTarget(name: "eventtap-spike", path: "Sources/EventTapSpike"),
        .executableTarget(name: "capture-spike", path: "Sources/CaptureSpike"),
        .executableTarget(
            name: "smc-probe",
            path: "Sources/SMCProbe",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
    ]
)
