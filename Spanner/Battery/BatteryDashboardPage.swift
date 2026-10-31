import SpannerCore
import SwiftUI

/// Main-window battery dashboard.
struct BatteryDashboardPage: View {
    @Environment(BatteryService.self) private var battery

    var body: some View {
        Page {
            PageHeader(title: "Battery",
                       subtitle: "Charge, power flow, health and charger details, updated live.",
                       symbol: AppSection.battery.symbol, tint: FeatureTint.battery)

            if let snapshot = battery.snapshot {
                HeroCard(snapshot: snapshot)
                if let flow = battery.flow {
                    PowerFlowCard(flow: flow, snapshot: snapshot)
                }
                HStack(alignment: .top, spacing: Spacing.l) {
                    HealthCard(snapshot: snapshot)
                    ChargerCard(charger: snapshot.charger)
                }
                DetailsCard(snapshot: snapshot)
                BatteryHistoryCard(history: battery.history)
                if !battery.accessories.isEmpty {
                    AccessoriesCard(accessories: battery.accessories)
                }
            } else if battery.hasBattery == false {
                Card {
                    EmptyStateView(symbol: "powerplug.portrait",
                                   title: "No battery",
                                   message: "This Mac runs on mains power only, so there's no battery to show.")
                }
                if !battery.accessories.isEmpty {
                    AccessoriesCard(accessories: battery.accessories)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .onAppear { battery.isDashboardVisible = true }
        .onDisappear { battery.isDashboardVisible = false }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        let tint = BatteryStyle.tint(for: snapshot)
        Card(padding: Spacing.xl) {
            HStack(alignment: .center, spacing: Spacing.xxl) {
                BatteryGlyph(percent: snapshot.percent, tint: tint, isCharging: snapshot.isCharging, width: 136)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("\(snapshot.percent)%")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(snapshot.percent)))
                    Text(snapshot.statusText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    pills(tint: tint)
                    if let explanation = snapshot.notChargingExplanation {
                        Label(explanation, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .animation(.spanner, value: snapshot.percent)
        .animation(.spanner, value: snapshot.state)
    }

    @ViewBuilder
    private func pills(tint: Color) -> some View {
        HStack(spacing: Spacing.s) {
            if let charger = snapshot.charger {
                StatusPill(text: charger.displayName, symbol: "bolt.fill", tint: .yellow)
            }
            switch snapshot.level {
            case .critical where !snapshot.isPluggedIn:
                StatusPill(text: "Critically low", symbol: "exclamationmark.triangle.fill", tint: .red)
            case .low where !snapshot.isPluggedIn:
                StatusPill(text: "Low battery", symbol: "battery.25percent", tint: .orange)
            default:
                EmptyView()
            }
            if snapshot.optimizedChargingEngaged {
                StatusPill(text: "Optimized Charging", symbol: "leaf.fill", tint: .green)
            }
        }
    }
}

// MARK: - Power flow

private struct PowerFlowCard: View {
    let flow: PowerFlow
    let snapshot: BatterySnapshot

    var body: some View {
        Card(padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CardTitle(title: "Power Flow", symbol: "bolt.horizontal.fill")
                PowerFlowView(flow: flow, isPluggedIn: snapshot.isPluggedIn,
                              chargerName: snapshot.charger?.displayName, batteryPercent: snapshot.percent)
                if let loss = flow.adapterLossWatts {
                    Text("About \(BatteryFormat.watts(loss)) is lost as heat converting the charger's voltage.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Health

private struct HealthCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "Health", symbol: "heart.fill")
                if let health = snapshot.health {
                    let tint = BatteryStyle.healthTint(health)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(health, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("of original capacity")
                            .foregroundStyle(.secondary)
                    }
                    MeterBar(fraction: health, tint: tint, height: 8)
                    if let max = snapshot.maxCapacity, let design = snapshot.designCapacity {
                        Text("Holds \(BatteryFormat.milliampHours(max)) of \(BatteryFormat.milliampHours(design)) when new")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Capacity data isn't available on this Mac.")
                        .foregroundStyle(.secondary)
                }

                if let cycles = snapshot.cycleCount {
                    Divider()
                    HStack {
                        Text("Charge cycles")
                        Spacer()
                        Text(cyclesText(cycles))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if let fraction = snapshot.cycleFraction {
                        MeterBar(fraction: fraction, tint: .blue, height: 5)
                    }
                }

                Text("Measured from the battery's raw capacity. System Settings' “Maximum Capacity” is calculated differently and can read higher.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cyclesText(_ cycles: Int) -> String {
        if let design = snapshot.designCycleCount {
            return "\(cycles.formatted()) of \(design.formatted())"
        }
        return cycles.formatted()
    }
}

// MARK: - Charger

private struct ChargerCard: View {
    let charger: ChargerInfo?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "Charger", symbol: "powerplug.portrait.fill")
                if let charger {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(charger.displayName)
                            .font(.title3.weight(.semibold))
                        if let negotiated = charger.negotiatedText {
                            Text("Negotiated \(negotiated)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if !charger.profiles.isEmpty {
                        Divider()
                        Text("USB-C power profiles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(spacing: Spacing.xxs) {
                            ForEach(charger.profiles) { profile in
                                ProfileRow(profile: profile, isActive: profile.index == charger.activeProfileIndex)
                            }
                        }
                    }
                } else {
                    EmptyStateView(symbol: "powerplug.portrait",
                                   title: "Not connected",
                                   message: "Plug in a charger to see its wattage and USB-C power profiles.")
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: PDProfile
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
            Text("\(BatteryFormat.volts(profile.voltage, digits: 0)) · \(BatteryFormat.amps(profile.current))")
                .monospacedDigit()
            Spacer()
            Text(BatteryFormat.watts(profile.watts))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear,
                    in: .rect(cornerRadius: CornerRadius.s, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Details

private struct DetailsCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "Details", symbol: "list.bullet.rectangle")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.l, alignment: .topLeading)],
                          alignment: .leading, spacing: Spacing.l) {
                    if let voltage = snapshot.voltage {
                        StatTile(title: "Voltage", value: BatteryFormat.volts(voltage),
                                 symbol: "bolt", tint: .yellow)
                    }
                    if let amperage = snapshot.amperage {
                        StatTile(title: "Current", value: BatteryFormat.amps(amperage, signed: true),
                                 detail: amperage >= 0 ? "Into battery" : "Out of battery",
                                 symbol: "arrow.left.arrow.right", tint: .blue)
                    }
                    if let watts = snapshot.batteryWatts {
                        StatTile(title: "Battery power", value: BatteryFormat.watts(abs(watts)),
                                 symbol: "bolt.batteryblock", tint: .green)
                    }
                    if let temperature = snapshot.temperature {
                        StatTile(title: "Temperature", value: BatteryFormat.celsius(temperature),
                                 detail: temperature >= 40 ? "Warm" : nil,
                                 symbol: "thermometer.medium", tint: temperature >= 40 ? .orange : .red)
                    }
                    StatTile(title: timeTitle, value: timeValue, symbol: "clock", tint: .purple)
                    if let current = snapshot.currentCapacity {
                        StatTile(title: "Charge", value: BatteryFormat.milliampHours(current),
                                 symbol: "battery.75percent", tint: .green)
                    }
                }
            }
        }
    }

    private var timeTitle: String {
        snapshot.isPluggedIn ? "Time to full" : "Time remaining"
    }

    private var timeValue: String {
        let minutes = snapshot.isPluggedIn ? snapshot.minutesToFull : snapshot.minutesToEmpty
        if let minutes { return SpannerFormat.duration(Double(minutes) * 60) }
        switch snapshot.state {
        case .full: return "Full"
        case .pluggedNotCharging: return "Paused"
        default: return "Calculating…"
        }
    }
}

// MARK: - Accessories

private struct AccessoriesCard: View {
    let accessories: [AccessoryBattery]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "Accessories", symbol: "keyboard")
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

/// Small heading used at the top of each battery card.
struct CardTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
    }
}
