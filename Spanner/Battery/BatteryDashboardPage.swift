import SpannerCore
import SwiftUI

/// Main-window battery dashboard.
struct BatteryDashboardPage: View {
    @Environment(BatteryService.self) private var battery
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Page {
            if let snapshot = battery.snapshot {
                SummaryCard(snapshot: snapshot, flow: battery.flow)
                BatteryHistoryCard(history: battery.history)
                EnergyCard()
                HealthCard(snapshot: snapshot)
                if let charger = snapshot.charger {
                    ChargerCard(charger: charger)
                }
                if !battery.accessories.isEmpty {
                    AccessoriesCard(accessories: battery.accessories)
                }
            } else if battery.hasBattery == false {
                Card {
                    EmptyStateView(symbol: "powerplug.portrait",
                                   title: "No battery",
                                   message: "This Mac runs on mains power only, so there's no battery to show.")
                }
                EnergyCard()
                if !battery.accessories.isEmpty {
                    AccessoriesCard(accessories: battery.accessories)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            HeadphonesGroup()
        }
        .animation(.spanner, value: battery.snapshot?.charger == nil)
        // Fast polling only while the window is in the active app: each
        // sample animates numbers across the page, which costs ~20% of a
        // core when the dashboard is left open behind other windows.
        .onAppear { battery.isDashboardVisible = appearsActive }
        .onChange(of: appearsActive) { _, active in battery.isDashboardVisible = active }
        .onDisappear { battery.isDashboardVisible = false }
    }
}

// MARK: - Headphones

private struct HeadphonesGroup: View {
    @Environment(HeadphoneMonitor.self) private var headphones
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        @Bindable var headphones = headphones
        let granted = permissions.isGranted(.bluetooth)
        SettingsGroup(title: "Headphones",
                      footer: granted
                          ? "To show or hide headphones in the menu bar panel, use the Menu Bar page. Nothing leaves your Mac."
                          : "Grant Bluetooth to read your AirPods' and headphones' battery. Nothing leaves your Mac.") {
            if !granted {
                PermissionRow(permission: .bluetooth)
            }
            SettingsRow(title: "Show battery when you put them on",
                        subtitle: "Pops up on screen when you put your AirPods in, or when other headphones connect.",
                        symbol: "airpods.pro", tint: FeatureTint.switcher) {
                Toggle("Show battery when you put them on", isOn: $headphones.showsHUD)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!granted)
            }
        }
        .animation(.spanner, value: granted)
    }
}

// MARK: - Summary

/// The page's opening card: charge and status in words, then where the power
/// is going. The toolbar already names the page, so this takes the place of a
/// page header.
private struct SummaryCard: View {
    let snapshot: BatterySnapshot
    let flow: PowerFlow?

    /// Losses under this round to "0.0 W", which reads as a mistake.
    private static let smallestLossShown = 0.05

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .center, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // Proportional digits: fixed-width ones centre a
                        // leading "1" in its cell, which indents the number
                        // from the status line under it.
                        Text("\(snapshot.percent)%")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(snapshot.percent)))
                        Text(snapshot.statusText)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                        notices
                            .font(.callout)
                            .padding(.top, Spacing.xs)
                    }
                    Spacer(minLength: 0)
                    BatteryGlyph(percent: snapshot.percent, tint: BatteryStyle.tint(for: snapshot),
                                 isCharging: snapshot.isCharging, width: 112)
                }
                .padding(.vertical, Spacing.s)
                if let flow {
                    Divider()
                    PowerFlowView(flow: flow, isPluggedIn: snapshot.isPluggedIn,
                                  chargerName: snapshot.charger?.displayName, batteryPercent: snapshot.percent)
                    if let loss = flow.adapterLossWatts, loss >= Self.smallestLossShown {
                        Text("About \(BatteryFormat.watts(loss)) is lost as heat converting the charger's voltage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.spanner, value: snapshot.percent)
        .animation(.spanner, value: snapshot.state)
    }

    /// Things worth a sentence under the status: a low charge, or why a
    /// plugged-in Mac isn't charging.
    @ViewBuilder
    private var notices: some View {
        if !snapshot.isPluggedIn {
            switch snapshot.level {
            case .critical:
                Label("Critically low", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .low:
                Label("Low battery", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .normal:
                EmptyView()
            }
        }
        if let explanation = snapshot.notChargingExplanation {
            Label(explanation, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if snapshot.optimizedChargingEngaged {
            Label("Optimized Charging is on", systemImage: "leaf")
                .foregroundStyle(.secondary)
        }
    }
}

/// An ⓘ button that explains a figure on demand, so the explanation doesn't
/// sit on the page as small print.
private struct InfoButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button("About this figure", systemImage: "info.circle") { isPresented = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(Spacing.l)
            }
    }
}

// MARK: - Health

/// The battery's slow-moving facts and raw readings. Power in watts is in the
/// flow diagram above, so only the volts and amps behind it are listed here.
private struct HealthCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        FactCard(title: "Battery") {
            if let health = snapshot.health {
                LabeledContent {
                    Text("\(healthText(health))\(capacityText)")
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Health")
                        InfoButton(text: "Measured from the battery's raw capacity against its capacity when new. System Settings' “Maximum Capacity” is calculated differently and can read higher.")
                    }
                }
            }
            if let cycles = snapshot.cycleCount {
                LabeledContent("Cycle count", value: cyclesText(cycles))
            }
            if let temperature = snapshot.temperature {
                LabeledContent("Temperature") {
                    Text("\(BatteryFormat.celsius(temperature)) · \(bandText(TemperatureBand(celsius: temperature)))")
                }
            }
            if let current = snapshot.currentCapacity {
                LabeledContent("Stored charge", value: BatteryFormat.milliampHours(current))
            }
            if let voltage = snapshot.voltage {
                LabeledContent("Voltage", value: BatteryFormat.volts(voltage))
            }
            if let amperage = snapshot.amperage {
                LabeledContent("Current", value: BatteryFormat.amps(amperage, signed: true))
                    .help("Positive while the battery is charging, negative while it powers the Mac.")
            }
        }
    }

    /// The percentage, coloured only once the battery is worn enough to matter.
    private func healthText(_ health: Double) -> Text {
        let text = Text(health, format: .percent.precision(.fractionLength(0)))
        return health < 0.8 ? text.foregroundStyle(BatteryStyle.healthTint(health)) : text
    }

    private var capacityText: String {
        guard let max = snapshot.maxCapacity, let design = snapshot.designCapacity else { return "" }
        return " · \(BatteryFormat.grouped(max)) of \(BatteryFormat.milliampHours(design))"
    }

    private func cyclesText(_ cycles: Int) -> String {
        if let design = snapshot.designCycleCount {
            return "\(BatteryFormat.grouped(cycles)) of \(BatteryFormat.grouped(design))"
        }
        return BatteryFormat.grouped(cycles)
    }

    /// The band in words, coloured only when it isn't the normal one.
    private func bandText(_ band: TemperatureBand) -> Text {
        switch band {
        case .cool: Text("Cool").foregroundStyle(.blue)
        case .normal: Text("Normal")
        case .warm: Text("Warm").foregroundStyle(.orange)
        case .hot: Text("Hot").foregroundStyle(.red)
        }
    }
}

// MARK: - Charger

private struct ChargerCard: View {
    let charger: ChargerInfo

    var body: some View {
        FactCard(title: "Charger") {
            LabeledContent("Adapter", value: charger.displayName)
            // With profiles listed, the ticked one already gives these values.
            if charger.activeProfile == nil, let negotiated = charger.negotiatedText {
                LabeledContent("Negotiated", value: negotiated)
            }
            if !charger.profiles.isEmpty {
                LabeledContent("USB-C power profiles") {
                    ProfileList(profiles: charger.profiles, activeIndex: charger.activeProfileIndex)
                }
            }
        }
    }
}

/// The voltages the charger offers, with a tick on the one in use.
private struct ProfileList: View {
    let profiles: [PDProfile]
    let activeIndex: Int?

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xs) {
            ForEach(profiles) { profile in
                let isActive = profile.index == activeIndex
                GridRow {
                    Group {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .opacity(isActive ? 1 : 0)
                            .accessibilityLabel("In use")
                            .accessibilityHidden(!isActive)
                        Text(BatteryFormat.volts(profile.voltage, digits: 0))
                        Text(BatteryFormat.amps(profile.current))
                        Text(BatteryFormat.watts(profile.watts))
                    }
                    .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Accessories

private struct AccessoriesCard: View {
    let accessories: [AccessoryBattery]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "Accessories")
                ForEach(accessories) { accessory in
                    HStack(spacing: Spacing.m) {
                        SymbolTile(symbol: symbol(for: accessory.kind), tint: .gray, size: 28)
                        Text(accessory.name)
                        Spacer(minLength: Spacing.l)
                        MeterBar(fraction: Double(accessory.percent) / 100,
                                 tint: BatteryStyle.tint(for: accessory.level))
                            .frame(width: 120)
                        Text("\(accessory.percent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func symbol(for kind: AccessoryBattery.Kind) -> String {
        switch kind {
        case .keyboard: "keyboard"
        case .mouse: "magicmouse.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}
