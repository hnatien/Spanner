<div align="center">

```
███████╗██████╗  █████╗ ███╗   ██╗███╗   ██╗███████╗██████╗
██╔════╝██╔══██╗██╔══██╗████╗  ██║████╗  ██║██╔════╝██╔══██╗
███████╗██████╔╝███████║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝
╚════██║██╔═══╝ ██╔══██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗
███████║██║     ██║  ██║██║ ╚████║██║ ╚████║███████╗██║  ██║
╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝
```

**One menu-bar app. All the little fixes macOS forgot.**

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Status](https://img.shields.io/badge/status-early%20development-orange)
![Distribution](https://img.shields.io/badge/distribution-direct%20only-blue)

</div>

```
╭─────────────────────────────────────────────────────────────────╮
│  ✻ Welcome to Spanner                                           │
│                                                                 │
│    ⌥⇥   Window switcher   every window, every Space, previews   │
│    ▮▮▯  Battery           health, cycles, watts, power flow     │
│    ◐    Keep Awake        caffeinate, one click away            │
│                                                                 │
│  ›  lives in your menu bar · v0.1.0                             │
╰─────────────────────────────────────────────────────────────────╯
```

---

## What's inside

| Module | What it does | Permissions |
|---|---|---|
| **Window switcher** | Windows-style `⌥⇥` switcher with live thumbnails for every window across screens and Spaces, including minimized ones. Per-app window cycling, configurable trigger, thumbnail size, and which screen the overlay opens on. Can take over `⌘⇥`, and restores it when Spanner quits or on the next launch after a crash. | Accessibility, Screen Recording |
| **Battery** | Charge, health against design capacity, cycle count, temperature, voltage and amperage, a live power-flow view (adapter → system → battery), charger wattage and USB-C PD profiles, charge history, and Magic Keyboard, Mouse and Trackpad batteries. | None |
| **Keep Awake** | Holds an IOKit power assertion (the same mechanism as `caffeinate`) for 15 min up to indefinitely, optionally keeping the display on. | None |

Spanner also ships onboarding, a permissions page with live status, launch-at-login, and Sparkle updates (dormant until a signed appcast exists).

> [!NOTE]
> Spanner relies on private SkyLight/CGS APIs for the switcher, so it is **direct distribution only** — no Mac App Store edition. Charge limiting is out of scope for now: firmware shipped with macOS 27 locks the charge-control SMC keys even for root. See the [feasibility report](docs/macOS%20utilities%20app%20feasibility.md).

## Getting started

Requirements: macOS 15 or later, Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Spanner.xcodeproj
```

macOS ties Accessibility and Screen Recording grants to the app's code signature. Ad-hoc builds get a new identity on every rebuild, so grants stop matching. To sign with your Apple Development certificate and keep grants across rebuilds:

```bash
scripts/setup-signing.sh
```

This writes the git-ignored `Config/Local.xcconfig`. Without it, builds fall back to ad-hoc signing.

## Tests

Platform-independent logic lives in the `SpannerKit` package so it can be tested without the app:

```bash
swift test --package-path Packages/SpannerKit
```

## Project layout

```
Spanner/
├── Spanner/                 the macOS app (SwiftUI + AppKit)
│   ├── App/                 entry point, app model, main window, login item
│   ├── MenuBar/             menu-bar panel and status icon
│   ├── Switcher/            hotkeys, window inventory, thumbnails, overlay
│   ├── Battery/             IOKit readers, dashboard, history
│   ├── KeepAwake/           power assertions and controls
│   ├── Permissions/         TCC status and prompts
│   ├── Onboarding/          first-launch guide
│   ├── Settings/            settings pages
│   ├── Updates/             Sparkle integration
│   └── DesignSystem/        tokens and shared components
├── Packages/SpannerKit/     testable core logic + CSMC, a tiny AppleSMC shim
├── prototypes/              Phase 0 spikes: hotkey, event tap, capture, SMC
├── docs/                    feasibility research and Phase 0 results
├── scripts/                 signing setup, icon generator
└── project.yml              XcodeGen spec (Spanner.xcodeproj is generated)
```

## Research

Spanner started from a feasibility study, then a round of throwaway spikes to answer the open questions before building:

- [macOS utilities app feasibility](docs/macOS%20utilities%20app%20feasibility.md) — switcher internals, battery APIs, the macOS 27 charge-limit lockdown, 30 QoL modules ranked, distribution, and the roadmap.
- [Phase 0 results](docs/Phase%200%20results.md) — what actually works on macOS 27.2: `⌘⇥` takeover, event-tap permissions, SMC keys, off-screen window capture.

<div align="center"><sub>Tighten what macOS left loose.</sub></div>
