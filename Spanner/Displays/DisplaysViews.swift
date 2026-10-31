import SwiftUI

/// Main-window page for external displays.
struct DisplaysPage: View {
    @Environment(DisplayController.self) private var displays

    var body: some View {
        @Bindable var displays = displays
        Page {
            PageHeader(title: "Displays",
                       subtitle: "Brightness and volume for external monitors, from Spanner or your keyboard's keys.",
                       symbol: AppSection.displays.symbol, tint: FeatureTint.displays)

            if displays.displays.isEmpty {
                Card {
                    EmptyStateView(symbol: "display.trianglebadge.exclamationmark", title: "No external display",
                                   message: "Connect a monitor over USB-C, Thunderbolt or DisplayPort. Your Mac's own display is controlled by macOS.")
                }
            } else {
                ForEach(displays.displays) { display in
                    DisplayCard(display: display)
                }
            }

            SettingsGroup(title: "Keyboard",
                          footer: "Volume keys reach a monitor only while sound plays through its speakers. Hold ⌥⇧ for finer steps.") {
                SettingsRow(title: "Use brightness and volume keys", symbol: "keyboard", tint: FeatureTint.displays) {
                    Toggle("Use brightness and volume keys", isOn: $displays.mediaKeysEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Brightness keys change", symbol: "sun.max", tint: .orange) {
                    Picker("Brightness keys change", selection: $displays.brightnessKeyTarget) {
                        ForEach(DisplayController.BrightnessKeyTarget.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!displays.mediaKeysEnabled)
                }
            }

            if displays.mediaKeysEnabled {
                MissingPermissionsGroup(needed: [.accessibility],
                                        footer: "Spanner needs Accessibility to receive the brightness and volume keys. The sliders above work without it.")
            }

            Text("Some monitors don't support DDC/CI, or have it switched off in their own menu. DDC also doesn't work over the HDMI port of M1 Macs and the entry-level M2 Mac mini; use USB-C or DisplayPort.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: displays.refreshDisplays)
    }
}

private struct DisplayCard: View {
    @Environment(DisplayController.self) private var displays
    let display: ExternalDisplay

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    SymbolTile(symbol: "display", tint: FeatureTint.displays, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(display.name).font(.headline)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if display.isReading {
                        ProgressView().controlSize(.small)
                    }
                }
                if display.hasDDC {
                    LevelSlider(title: "Brightness", lowSymbol: "sun.min", highSymbol: "sun.max.fill",
                                value: display.brightness) { displays.setBrightness($0, for: display.id) }
                    LevelSlider(title: "Volume", lowSymbol: "speaker.fill", highSymbol: "speaker.wave.3.fill",
                                value: display.isMuted ? 0 : display.volume) { displays.setVolume($0, for: display.id) }
                }
            }
        }
    }

    private var status: String {
        if !display.hasDDC { return "Spanner can't reach this display's controls." }
        if display.isReading { return "Reading current levels…" }
        if display.brightness == nil { return "The display didn't report its levels; adjusting still works." }
        return "Controlled over DDC/CI"
    }
}

private struct LevelSlider: View {
    let title: String
    let lowSymbol: String
    let highSymbol: String
    let value: Double?
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(title).frame(width: 80, alignment: .leading)
            Image(systemName: lowSymbol).foregroundStyle(.secondary)
            Slider(value: Binding(get: { value ?? 0.5 }, set: { onChange($0) }), in: 0...1) { Text(title) }
                .labelsHidden()
            Image(systemName: highSymbol).foregroundStyle(.secondary)
            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Brightness sliders for the menu bar panel, one per controllable monitor.
struct DisplaysMenuSection: View {
    @Environment(DisplayController.self) private var displays

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(displays.displays.filter(\.hasDDC)) { display in
                HStack(spacing: Spacing.m) {
                    SymbolTile(symbol: "sun.max.fill", tint: FeatureTint.displays, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name).font(.callout.weight(.medium)).lineLimit(1)
                        Slider(value: Binding(get: { display.brightness ?? 0.5 },
                                              set: { displays.setBrightness($0, for: display.id) }),
                               in: 0...1) { Text("\(display.name) brightness") }
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
