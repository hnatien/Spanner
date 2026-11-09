import SpannerCore
import SwiftUI

/// Main-window battery dashboard.
struct BatteryDashboardPage: View {
    @Environment(BatteryService.self) private var battery
    @Environment(\.appearsActive) private var appearsActive

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
                EnergyCard()
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

/// Groups the raw readings by what they mean: how much power the battery
/// moves (and the volts × amps behind it), how much charge is stored, and
/// whether the temperature is in a healthy range.
private struct DetailsCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CardTitle(title: "Details", symbol: "list.bullet.rectangle")
                if snapshot.voltage != nil || snapshot.amperage != nil {
                    ElectricalSection(snapshot: snapshot)
                }
                HStack(alignment: .top, spacing: Spacing.xl) {
                    ChargeSection(snapshot: snapshot)
                    if let temperature = snapshot.temperature {
                        TemperatureSection(celsius: temperature)
                    }
                }
            }
        }
    }
}

private struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct DetailValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
    }
}

/// "↑ 39.3 W drawn from the battery", with the volts × amps it comes from
/// underneath for anyone who wants the raw readings.
private struct ElectricalSection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                if let watts {
                    Label(BatteryFormat.watts(watts), systemImage: direction.symbol)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: watts))
                        .foregroundStyle(direction.tint)
                        .lineLimit(1)
                    Text(direction.text)
                        .foregroundStyle(.secondary)
                } else {
                    // Only one of volts or amps was reported, so there's no power to lead with.
                    DetailValue(text: readings)
                }
            }
            if watts != nil {
                Text(readings)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Watts from the volts and amps shown, so the two lines add up.
    private var watts: Double? {
        guard let voltage = snapshot.voltage, let amperage = snapshot.amperage else { return nil }
        return Double(voltage) * Double(abs(amperage)) / 1_000_000
    }

    /// "12.64 V × 3.11 A", or whichever of the two is known.
    private var readings: String {
        [snapshot.voltage.map { BatteryFormat.volts($0) },
         snapshot.amperage.map { BatteryFormat.amps(abs($0)) }]
            .compactMap(\.self)
            .joined(separator: " × ")
    }

    private var direction: (text: String, symbol: String, tint: Color) {
        let amperage = snapshot.amperage ?? 0
        if amperage > 0 { return ("flowing into the battery", "arrow.down", .green) }
        if amperage < 0 { return ("drawn from the battery", "arrow.up", .orange) }
        return ("battery idle", "pause", .secondary)
    }
}

/// Stored mAh against the full-charge capacity, plus when it fills or runs out.
private struct ChargeSection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DetailSectionTitle(title: "Stored charge")
            if let current = snapshot.currentCapacity {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    DetailValue(text: BatteryFormat.milliampHours(current))
                    if let max = snapshot.maxCapacity {
                        Text("of \(BatteryFormat.milliampHours(max))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                DetailValue(text: "\(snapshot.percent)%")
            }
            MeterBar(fraction: snapshot.chargeFraction ?? Double(snapshot.percent) / 100,
                     tint: BatteryStyle.tint(for: snapshot))
                .padding(.vertical, Spacing.xxs)
            timeText
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeText: Text {
        // The hero already shows the exact estimate; here it's rounded, since
        // it swings by minutes with every change in load.
        let minutes = snapshot.isPluggedIn ? snapshot.minutesToFull : snapshot.minutesToEmpty
        if let minutes {
            let duration = BatteryFormat.roughDuration(minutes: minutes)
            return snapshot.isPluggedIn
                ? Text("Full in about \(duration)")
                : Text("About \(duration) left at this rate")
        }
        switch snapshot.state {
        case .full: return Text("Fully charged")
        case .pluggedNotCharging: return Text("Charging paused")
        default: return Text("Estimating time…")
        }
    }
}

/// Temperature with a cool / normal / warm scale and a marker for the reading.
private struct TemperatureSection: View {
    let celsius: Double

    var body: some View {
        let band = TemperatureBand(celsius: celsius)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DetailSectionTitle(title: "Temperature")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                DetailValue(text: BatteryFormat.celsius(celsius))
                Text(Self.label(band))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Self.tint(band))
            }
            TemperatureScale(celsius: celsius)
                .padding(.vertical, Spacing.xxs)
            TemperatureTicks()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature")
        .accessibilityValue("\(BatteryFormat.celsius(celsius)), \(Self.label(band))")
    }

    static func label(_ band: TemperatureBand) -> String {
        switch band {
        case .cool: "Cool"
        case .normal: "Normal"
        case .warm: "Warm"
        case .hot: "Hot"
        }
    }

    static func tint(_ band: TemperatureBand) -> Color {
        switch band {
        case .cool: .blue
        case .normal: .green
        case .warm: .orange
        case .hot: .red
        }
    }
}

private struct TemperatureScale: View {
    let celsius: Double
    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    segment(.cool, from: TemperatureBand.scale.lowerBound, to: TemperatureBand.normalFrom, width: width)
                    segment(.normal, from: TemperatureBand.normalFrom, to: TemperatureBand.warmFrom, width: width)
                    segment(.warm, from: TemperatureBand.warmFrom, to: TemperatureBand.hotFrom, width: width)
                    segment(.hot, from: TemperatureBand.hotFrom, to: TemperatureBand.scale.upperBound, width: width)
                }
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: height + 6)
                    .offset(x: width * TemperatureBand.scaleFraction(celsius) - 1.5)
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
        .animation(.spanner, value: celsius)
    }

    private func segment(_ band: TemperatureBand, from: Double, to: Double, width: CGFloat) -> some View {
        Capsule()
            .fill(TemperatureSection.tint(band).opacity(0.45))
            .frame(width: max(0, width * (TemperatureBand.scaleFraction(to) - TemperatureBand.scaleFraction(from)) - 2),
                   height: height)
    }
}

/// Degree labels under `TemperatureScale`, each centred on the band edge it marks.
private struct TemperatureTicks: View {
    var body: some View {
        GeometryReader { proxy in
            ForEach([TemperatureBand.normalFrom, TemperatureBand.warmFrom, TemperatureBand.hotFrom], id: \.self) { celsius in
                Text("\(Int(celsius))°")
                    .fixedSize()
                    .position(x: proxy.size.width * TemperatureBand.scaleFraction(celsius),
                              y: proxy.size.height / 2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(height: 16)
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
