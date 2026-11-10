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

/// Charger → Mac → Battery diagram with live watts under each wire and dots
/// moving along it in the direction power flows.
///
/// Drawn in one colour, with the battery's wire the only tinted part: green
/// while it charges, orange while it drains.
struct PowerFlowView: View {
    let flow: PowerFlow
    let isPluggedIn: Bool
    let chargerName: String?
    let batteryPercent: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FlowNode(symbol: "powerplug.portrait", title: "Charger",
                     value: isPluggedIn ? (chargerName ?? "Connected") : "Not connected",
                     dimmed: !isPluggedIn)
            FlowConnector(watts: flow.adapterWatts, direction: isPluggedIn ? .forward : .idle, tint: .secondary)
            FlowNode(symbol: "laptopcomputer", title: "Mac",
                     value: flow.systemWatts.map { "Using \(BatteryFormat.watts($0))" } ?? "—")
            FlowConnector(watts: flow.batteryWatts.flatMap { flow.batteryDirection == .idle ? nil : $0 },
                          direction: batteryConnectorDirection,
                          tint: flow.batteryDirection == .discharging ? .orange : .green)
            // The block symbol, so the charge glyph above stays the only battery
            // drawn with a level.
            FlowNode(symbol: "minus.plus.batteryblock", title: "Battery", value: batteryCaption)
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

/// Height shared by the node symbols and the wires, so a wire meets its
/// symbols at their centre when the row is top-aligned.
private let flowRowHeight: CGFloat = 32

private struct FlowNode: View {
    let symbol: String
    let title: String
    let value: String
    var dimmed = false

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(dimmed ? .tertiary : .primary)
                .frame(height: flowRowHeight)
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

/// A wire between two nodes, with the wattage it carries underneath. While
/// power flows, dots travel along it, faster as the wattage rises. Static
/// when Reduce Motion is on, and paused while the window isn't in the active
/// app: a dashboard left open behind other windows otherwise redraws at the
/// display's refresh rate and costs ~40% of a core for nobody to see.
private struct FlowConnector: View {
    enum Direction { case forward, backward, idle }

    let watts: Double?
    let direction: Direction
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var clock = FlowClock()

    /// Dots move at most ~2 pt per frame at 30 fps, which still reads as
    /// smooth; 120 Hz ProMotion would quadruple the cost for no visible gain.
    private static let frameInterval = 1.0 / 30
    private static let dotSpacing = 14.0

    var body: some View {
        VStack(spacing: Spacing.s) {
            TimelineView(.animation(minimumInterval: Self.frameInterval,
                                    paused: direction == .idle || reduceMotion || !appearsActive)) { context in
                Canvas { graphics, size in
                    draw(in: &graphics, size: size, date: context.date)
                }
            }
            .frame(height: flowRowHeight)
            // The arrow keeps the direction readable when the dots are still.
            HStack(spacing: Spacing.xs) {
                Text(watts.map(BatteryFormat.watts) ?? " ")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: direction == .backward ? "arrow.left" : "arrow.right")
                    .imageScale(.small)
                    .opacity(direction == .idle ? 0 : 1)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(direction == .idle ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 0…1 strength of the flow; square root so small loads still read as alive.
    private var level: Double {
        guard let watts else { return 0.5 }
        return min(1, (max(0, watts) / 100).squareRoot())
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, date: Date) {
        let y = size.height / 2
        // Drawn from the source end, so advancing the dash phase moves the
        // dots the way the power goes.
        let start = direction == .backward ? size.width : 0
        var wire = Path()
        wire.move(to: CGPoint(x: start, y: y))
        wire.addLine(to: CGPoint(x: size.width - start, y: y))
        graphics.stroke(wire, with: .color(.secondary.opacity(0.25)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        guard direction != .idle else { return }

        let travelled = reduceMotion ? 0 : clock.advance(to: date, speed: 18 + 52 * level)
        // A near-zero dash with round caps draws a dot.
        let phase = Self.dotSpacing - travelled.truncatingRemainder(dividingBy: Self.dotSpacing)
        graphics.stroke(wire, with: .color(tint),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round,
                                           dash: [0.01, Self.dotSpacing - 0.01], dashPhase: phase))
    }
}

/// Integrates distance travelled frame by frame so a change in speed (when
/// the wattage moves) eases in instead of making every pulse jump.
private final class FlowClock {
    private var lastDate: Date?
    private var speed: Double?
    private var phase = 0.0

    func advance(to date: Date, speed target: Double) -> Double {
        // Clamp the step so resuming after a pause doesn't teleport the pulses.
        let step = lastDate.map { min(1.0 / 15, max(0, date.timeIntervalSince($0))) } ?? 0
        lastDate = date
        let current = speed ?? target
        let eased = current + (target - current) * min(1, step * 2.5)
        speed = eased
        phase += eased * step
        return phase
    }
}
