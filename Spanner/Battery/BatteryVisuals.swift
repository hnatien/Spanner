import SpannerCore
import SwiftUI

/// Colour rules for battery surfaces: green while charging or healthy,
/// orange when low, red when critical.
enum BatteryStyle {
    static func tint(for snapshot: BatterySnapshot) -> Color {
        if snapshot.isCharging || snapshot.state == .full { return .green }
        return tint(for: snapshot.level)
    }

    static func tint(for level: ChargeLevel) -> Color {
        switch level {
        case .critical: .red
        case .low: .orange
        case .normal: .green
        }
    }

    /// Health colour: worn batteries turn orange, then red.
    static func healthTint(_ health: Double) -> Color {
        health >= 0.8 ? .green : health >= 0.6 ? .orange : .red
    }

    static func symbol(for snapshot: BatterySnapshot) -> String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        switch snapshot.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// A drawn battery whose fill tracks the charge, with a bolt while charging.
/// Drawn rather than an SF Symbol so the fill is continuous and animates.
struct BatteryGlyph: View {
    let percent: Int
    let tint: Color
    var isCharging = false
    var width: CGFloat = 120

    var body: some View {
        let height = width * 0.48
        let lineWidth = max(1.5, width * 0.03)
        let inset = lineWidth * 2
        HStack(spacing: width * 0.02) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: lineWidth)
                RoundedRectangle(cornerRadius: height * 0.26 - inset, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: max(height * 0.18, (width - inset * 2) * CGFloat(percent) / 100))
                    .padding(inset)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5)
                        .frame(maxWidth: .infinity)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: width, height: height)
            Capsule()
                .fill(.secondary.opacity(0.55))
                .frame(width: width * 0.04, height: height * 0.34)
        }
        .animation(.spanner, value: percent)
        .animation(.spanner, value: isCharging)
        .accessibilityElement()
        .accessibilityLabel("Battery")
        .accessibilityValue("\(percent) percent\(isCharging ? ", charging" : "")")
    }
}

/// Circular charge gauge for compact places (menu bar panel).
struct BatteryRing: View {
    let percent: Int
    let tint: Color
    var isCharging = false
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: isCharging ? "bolt.fill" : "battery.100percent")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(.spanner, value: percent)
        .accessibilityElement()
        .accessibilityLabel("Battery")
        .accessibilityValue("\(percent) percent\(isCharging ? ", charging" : "")")
    }
}

/// Charger → Mac → Battery diagram with live watts on each connector and
/// moving dots showing the direction power flows.
struct PowerFlowView: View {
    let flow: PowerFlow
    let isPluggedIn: Bool
    let chargerName: String?
    let batteryPercent: Int

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            FlowNode(symbol: "powerplug.portrait.fill", title: "Charger",
                     value: isPluggedIn ? (chargerName ?? "Connected") : "Not connected",
                     tint: isPluggedIn ? .yellow : .gray, dimmed: !isPluggedIn)
            FlowConnector(watts: flow.adapterWatts, direction: isPluggedIn ? .forward : .idle, tint: .yellow)
            FlowNode(symbol: "laptopcomputer", title: "Mac",
                     value: flow.systemWatts.map { "Using \(BatteryFormat.watts($0))" } ?? "—",
                     tint: FeatureTint.switcher)
            FlowConnector(watts: flow.batteryWatts.flatMap { flow.batteryDirection == .idle ? nil : $0 },
                          direction: batteryConnectorDirection, tint: .green)
            FlowNode(symbol: "battery.100percent", title: "Battery",
                     value: batteryCaption, tint: .green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power flow")
        .accessibilityValue(accessibilitySummary)
    }

    private var batteryConnectorDirection: FlowConnector.Direction {
        switch flow.batteryDirection {
        case .charging: .forward
        case .discharging: .backward
        case .idle: .idle
        }
    }

    private var batteryCaption: String {
        switch flow.batteryDirection {
        case .charging: "Charging · \(batteryPercent)%"
        case .discharging: "Powering Mac · \(batteryPercent)%"
        case .idle: "Idle · \(batteryPercent)%"
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let adapter = flow.adapterWatts { parts.append("Charger supplying \(BatteryFormat.watts(adapter))") }
        if let system = flow.systemWatts { parts.append("Mac using \(BatteryFormat.watts(system))") }
        if let battery = flow.batteryWatts {
            switch flow.batteryDirection {
            case .charging: parts.append("Battery charging at \(BatteryFormat.watts(battery))")
            case .discharging: parts.append("Battery supplying \(BatteryFormat.watts(battery))")
            case .idle: parts.append("Battery idle")
            }
        }
        return parts.joined(separator: ", ")
    }
}

private struct FlowNode: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color
    var dimmed = false

    var body: some View {
        VStack(spacing: Spacing.s) {
            SymbolTile(symbol: symbol, tint: tint, size: 44)
                .opacity(dimmed ? 0.4 : 1)
            VStack(spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 118)
    }
}

/// A line between two nodes with the current wattage above it and dots
/// travelling in the direction of flow. Static when Reduce Motion is on.
private struct FlowConnector: View {
    enum Direction { case forward, backward, idle }

    let watts: Double?
    let direction: Direction
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(watts.map(BatteryFormat.watts) ?? " ")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(direction == .idle ? .secondary : .primary)
            TimelineView(.animation(paused: direction == .idle || reduceMotion)) { context in
                Canvas { graphics, size in
                    let y = size.height / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    graphics.stroke(line, with: .color(.secondary.opacity(0.25)),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    guard direction != .idle else { return }

                    let spacing: CGFloat = 22
                    let speed: CGFloat = 26  // points per second
                    let phase = reduceMotion ? spacing / 2
                        : CGFloat(context.date.timeIntervalSinceReferenceDate * speed)
                            .truncatingRemainder(dividingBy: spacing)
                    var x = phase
                    while x < size.width {
                        let position = direction == .forward ? x : size.width - x
                        let fade = min(1, min(position, size.width - position) / 14)
                        let dot = Path(ellipseIn: CGRect(x: position - 3, y: y - 3, width: 6, height: 6))
                        graphics.fill(dot, with: .color(tint.opacity(0.9 * fade)))
                        x += spacing
                    }
                }
            }
            .frame(height: 8)
            Image(systemName: direction == .backward ? "arrow.left" : "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(direction == .idle ? .clear : tint.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)  // align the line with the node icons
    }
}
