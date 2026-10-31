// swift-tools-version: 6.0
import PackageDescription

// Platform-independent logic for Spanner, kept out of the app target so it can
// be unit tested with `swift test`, plus a small C shim for AppleSMC reads.
let package = Package(
    name: "SpannerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SpannerCore", targets: ["SpannerCore"]),
        .library(name: "CSMC", targets: ["CSMC"]),
    ],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "SpannerCore"),
        .testTarget(name: "SpannerCoreTests", dependencies: ["SpannerCore"]),
    ]
)
