<div align="center">

<img src="docs/assets/logo.png" alt="Spanner logo" width="168" height="168">

# Spanner

**One menu-bar app. All the little fixes macOS forgot.**

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111111?style=flat-square&logo=apple&logoColor=white)](#getting-started)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org)
[![Status](https://img.shields.io/badge/status-early%20development-6B5CF6?style=flat-square)](#research)
[![Distribution](https://img.shields.io/badge/distribution-direct%20only-3FA9F5?style=flat-square)](#getting-started)

[Features](#features) · [Getting started](#getting-started) · [Tests](#tests) · [Project layout](#project-layout) · [Research](#research)

</div>

<br>

## Features

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>⌥⇥&nbsp; Window switcher</h3>
      Windows-style switcher with live thumbnails for every window across screens and Spaces, minimized ones included.
      <br><br>
      <sub>Needs Accessibility + Screen Recording</sub>
    </td>
    <td width="33%" valign="top">
      <h3>🔋&nbsp; Battery</h3>
      Health, cycles, temperature, voltage, a live power-flow view, charger wattage and USB-C PD profiles, and charge history.
      <br><br>
      <sub>No permissions</sub>
    </td>
    <td width="33%" valign="top">
      <h3>☕&nbsp; Keep Awake</h3>
      Keeps your Mac, and optionally the display, awake for 15 minutes up to indefinitely, one click from the menu bar.
      <br><br>
      <sub>No permissions</sub>
    </td>
  </tr>
</table>

<details>
<summary><b>More detail</b></summary>

<br>

- **Window switcher:** per-app window cycling, a configurable trigger and thumbnail size, and a choice of which screen the overlay opens on. It can take over `⌘⇥`, and restores it when Spanner quits or on the next launch after a crash.
- **Battery:** the power-flow view shows adapter → system → battery from IOKit telemetry, without root. Also shows Magic Keyboard, Mouse and Trackpad batteries.
- **Keep Awake:** holds an IOKit power assertion, the same mechanism as `caffeinate`.
- **Around them:** onboarding, a permissions page with live status, launch at login, and Sparkle updates (dormant until a signed appcast exists).

</details>

> [!NOTE]
> The switcher relies on private SkyLight/CGS APIs, so Spanner is **direct distribution only**, with no Mac App Store edition. Charge limiting is out of scope for now: firmware shipped with macOS 27 locks the charge-control SMC keys even for root. See the [feasibility report](docs/macOS%20utilities%20app%20feasibility.md).

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
├── docs/                    feasibility research, Phase 0 results, logo
├── scripts/                 signing setup, icon and logo generators
└── project.yml              XcodeGen spec (Spanner.xcodeproj is generated)
```

## Research

Spanner started from a feasibility study, then a round of throwaway spikes to answer the open questions before building:

- [**macOS utilities app feasibility**](docs/macOS%20utilities%20app%20feasibility.md): switcher internals, battery APIs, the macOS 27 charge-limit lockdown, 30 QoL modules ranked, distribution, and the roadmap.
- [**Phase 0 results**](docs/Phase%200%20results.md): what actually works on macOS 27.2, covering the `⌘⇥` takeover, event-tap permissions, SMC keys, and off-screen window capture.

<br>

<div align="center">
<img src="docs/assets/logo.png" alt="" width="40" height="40">
<br>
<sub>Tighten what macOS left loose.</sub>
</div>
