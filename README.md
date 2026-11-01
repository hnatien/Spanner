<div align="center">

<img src="docs/assets/logo.png" alt="Spanner logo" width="168" height="168">

# Spanner

**One menu-bar app. All the little fixes macOS forgot.**

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111111?style=flat-square&logo=apple&logoColor=white)](#getting-started)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org)
![Status](https://img.shields.io/badge/status-early%20development-6B5CF6?style=flat-square)
[![Distribution](https://img.shields.io/badge/distribution-direct%20only-3FA9F5?style=flat-square)](#getting-started)

[Features](#features) · [Install](#install) · [Getting started](#getting-started) · [Tests](#tests) · [Project layout](#project-layout)

</div>

<br>

## Features

| Module | What it does | Permissions |
| :-- | :-- | :-- |
| 🔋&nbsp;**Battery** | Health, cycles, temperature, voltage, a live power-flow view, charger wattage and USB-C PD profiles, and charge history. | Bluetooth, for headphone battery only |
| ⌥⇥&nbsp;**Window&nbsp;switcher** | Windows-style switcher with live thumbnails for every window across screens and Spaces, minimized ones included. | Accessibility, Screen Recording |
| ⌃⌥←&nbsp;**Window&nbsp;snapping** | Halves, thirds, quarters and your own grid per display, from shortcuts or by dragging to an edge. | Accessibility |
| 🖱️&nbsp;**Mouse** | A wheel direction separate from the trackpad, smooth scrolling and button actions. | Accessibility |
| 🔊&nbsp;**Sound** | Per-app volume, device switching and a mic-mute shortcut. | System Audio Recording, for per-app volume only |
| ☀️&nbsp;**Displays** | Brightness and volume for external monitors over DDC/CI, from sliders or the keyboard's keys, with an on-screen display. | Accessibility, for the keyboard's keys only |
| ☕&nbsp;**Keep&nbsp;Awake** | Keeps your Mac, and optionally the display, awake for 15 minutes up to indefinitely, one click from the menu bar. | None |

<details>
<summary><b>More detail</b></summary>

<br>

- **Window switcher:** per-app window cycling, a configurable trigger and thumbnail size, and a choice of which screen the overlay opens on. It can take over `⌘⇥`, and restores it when Spanner quits or on the next launch after a crash.
- **Battery:** the power-flow view shows adapter → system → battery from IOKit telemetry, without root. Also shows Magic Keyboard, Mouse and Trackpad batteries.
- **Keep Awake:** holds an IOKit power assertion, the same mechanism as `caffeinate`.
- **Battery, energy by app:** power drawn by each app and its helpers, from the kernel's per-process energy counters.
- **Around them:** onboarding, a permissions page with live status, launch at login, and Sparkle updates.

</details>

> [!NOTE]
> The switcher relies on private SkyLight/CGS APIs, so Spanner is **direct distribution only**, with no Mac App Store edition. Charge limiting is out of scope for now: firmware shipped with macOS 27 locks the charge-control SMC keys even for root. See the [feasibility report](docs/macOS%20utilities%20app%20feasibility.md).

## Install

1. Download the latest `Spanner-<version>.dmg` from [Releases](https://github.com/hnatien/Spanner/releases/latest).
2. Spanner isn't notarized by Apple yet, so macOS refuses to open the DMG. Before opening it, clear the download's quarantine flag in Terminal:

   ```bash
   xattr -d com.apple.quarantine ~/Downloads/Spanner-*.dmg
   ```

   This also clears the app inside, so macOS won't block Spanner's first launch either. To skip Terminal instead, open the DMG, then go to **System Settings › Privacy & Security**, scroll down to the message about it, and click **Open Anyway**. You'll need to do the same again the first time you open Spanner.
3. Open the DMG, drag **Spanner** into **Applications**, and open it.
4. Grant the permissions each module asks for (Accessibility, Screen Recording, System Audio Recording) in the onboarding guide.

Later versions arrive through Spanner's built-in updater and don't need step 2 again.

## Getting started

You need macOS 15 or later, Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Spanner.xcodeproj
```

> [!TIP]
> macOS ties Accessibility and Screen Recording grants to the app's code signature. Ad-hoc builds get a new identity on every rebuild, so grants stop matching. Run `scripts/setup-signing.sh` once to sign with your Apple Development certificate and keep grants across rebuilds. It writes the git-ignored `Config/Local.xcconfig`; without it, builds fall back to ad-hoc signing.

## Tests

Platform-independent logic lives in the `SpannerKit` package, so it can be tested without the app:

```bash
swift test --package-path Packages/SpannerKit
```

## Project layout

```
Spanner/
├── Spanner/                 the macOS app (SwiftUI + AppKit)
│   ├── App/                 entry point, app model, main window, login item
│   ├── MenuBar/             menu-bar panel and status icon
│   ├── Switcher/            window inventory, thumbnails, overlay
│   ├── Snapping/            window snapping: shortcuts, drag zones, grids
│   ├── Mouse/               scroll direction, smooth scrolling, buttons
│   ├── Sound/               per-app volume (process taps), devices, mic mute
│   ├── Displays/            DDC brightness and volume, media keys
│   ├── Input/               shared hotkeys, event taps, shortcut recorder
│   ├── Battery/             IOKit readers, dashboard, history, energy by app
│   ├── KeepAwake/           power assertions and controls
│   ├── Permissions/         TCC status and prompts
│   ├── Onboarding/          first-launch guide
│   ├── Settings/            settings pages
│   ├── Updates/             Sparkle integration
│   └── DesignSystem/        tokens and shared components
├── Packages/SpannerKit/     testable core logic + CSMC, a tiny AppleSMC shim
├── prototypes/              Phase 0 spikes: hotkey, event tap, capture, SMC
├── docs/                    feasibility research, Phase 0 and 2 results, logo
├── scripts/                 signing setup, icon and logo generator
└── project.yml              XcodeGen spec (Spanner.xcodeproj is generated)
```

<br>

<div align="center">
<img src="docs/assets/logo.png" alt="" width="40" height="40">
<br>
<sub>Tighten what macOS left loose.</sub>
</div>
