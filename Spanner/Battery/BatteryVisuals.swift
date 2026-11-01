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

/// A line between two nodes with the current wattage above it and glowing
/// charge pulses travelling in the direction of flow. Pulses move faster,
/// grow and glow brighter as the wattage rises. Static when Reduce Motion is on,
/// and paused while the window isn't in the active app: a dashboard left open
/// behind other windows otherwise redraws at the display's refresh rate and
/// costs ~40% of a core for nobody to see.
private struct FlowConnector: View {
    enum Direction { case forward, backward, idle }

    let watts: Double?
    let direction: Direction
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var clock = FlowClock()

    /// Pulses move at most ~2 pt per frame at 30 fps, which still reads as
    /// smooth; 120 Hz ProMotion would quadruple the cost for no visible gain.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(watts.map(BatteryFormat.watts) ?? " ")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(direction == .idle ? .secondary : .primary)
            TimelineView(.animation(minimumInterval: Self.frameInterval,
                                    paused: direction == .idle || reduceMotion || !appearsActive)) { context in
                Canvas { graphics, size in
                    draw(in: &graphics, size: size, date: context.date)
                }
            }
            .frame(height: 20)
            Image(systemName: direction == .backward ? "arrow.left" : "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(direction == .idle ? .clear : tint.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)  // align the line with the node icons
    }

    /// 0…1 strength of the flow; square root so small loads still read as alive.
    private var level: Double {
        guard let watts else { return 0.5 }
        return min(1, (max(0, watts) / 100).squareRoot())
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, date: Date) {
        let y = size.height / 2
        var wire = Path()
        wire.move(to: CGPoint(x: 0, y: y))
        wire.addLine(to: CGPoint(x: size.width, y: y))
        graphics.stroke(wire, with: .color(.secondary.opacity(0.22)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
        guard direction != .idle else { return }

        // The energised wire carries a faint tint so the line itself looks live.
        graphics.stroke(wire, with: .color(tint.opacity(0.18 + 0.12 * level)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let phase = reduceMotion ? 0 : clock.advance(to: date, speed: 18 + 52 * level)
        let spacing = 20.0
        let tail = 6 + 12 * level
        let edge = 16.0
        let width = Double(size.width)
        let pulses = Self.pulses(phase: phase, spacing: spacing, width: width, tail: tail)
        let time = date.timeIntervalSinceReferenceDate

        func point(_ x: Double) -> CGPoint {
            CGPoint(x: direction == .forward ? x : width - x, y: y)
        }

        // Soft halo under the pulses: a radial falloff that reaches zero inside
        // the canvas, so it never gets clipped into a box the way a blur would.
        for pulse in pulses {
            let fade = min(1, max(0, min(pulse.x, width - pulse.x) / edge))
            guard fade > 0 else { continue }
            let alpha = (0.3 + 0.3 * level) * fade * pulse.brightness
            let r = min(y - 1, (5 + 2.5 * level) * pulse.scale)
            let center = point(pulse.x)
            let glow = Gradient(stops: [
                .init(color: tint.opacity(alpha), location: 0),
                .init(color: tint.opacity(alpha * 0.45), location: 0.35),
                .init(color: tint.opacity(alpha * 0.12), location: 0.7),
                .init(color: tint.opacity(0), location: 1),
            ])
            graphics.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                          with: .radialGradient(glow, center: center, startRadius: 0, endRadius: r))
        }

        for pulse in pulses {
            let fade = min(1, max(0, min(pulse.x, width - pulse.x) / edge))
            guard fade > 0 else { continue }
            let flicker = reduceMotion ? 1 : 0.85 + 0.15 * sin(time * 9 + Double(pulse.id))
            let alpha = fade * pulse.brightness * flicker
            let head = point(pulse.x)
            let r = (1.8 + 0.9 * level) * pulse.scale

            // Tapered trail fading out behind the head.
            var trail = Path()
            trail.move(to: point(pulse.x - tail * pulse.scale))
            trail.addLine(to: head)
            graphics.stroke(trail,
                            with: .linearGradient(Gradient(colors: [tint.opacity(0), tint.opacity(0.8 * alpha)]),
                                                  startPoint: point(pulse.x - tail * pulse.scale), endPoint: head),
                            style: StrokeStyle(lineWidth: r * 1.3, lineCap: .round))

            // Tinted head with a hot white core.
            graphics.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                          with: .color(tint.opacity(alpha)))
            let core = r * 0.5
            graphics.fill(Path(ellipseIn: CGRect(x: head.x - core, y: head.y - core, width: core * 2, height: core * 2)),
                          with: .color(.white.opacity(0.85 * alpha)))
        }
    }

    private struct Pulse {
        let id: Int
        let x: Double
        let scale: Double
        let brightness: Double
    }

    /// Pulses currently on the wire. Each keeps its id while it travels, so its
    /// jittered spacing, size and brightness stay stable instead of popping.
    private static func pulses(phase: Double, spacing: Double, width: Double, tail: Double) -> [Pulse] {
        let first = Int(((phase - width - tail) / spacing).rounded(.down)) - 1
        let last = Int((phase / spacing).rounded(.up)) + 1
        return (first...last).compactMap { id in
            let x = phase - Double(id) * spacing + (noise(id, 1) - 0.5) * spacing * 0.7
            guard x > -tail, x < width + tail else { return nil }
            return Pulse(id: id, x: x, scale: 0.75 + 0.45 * noise(id, 2), brightness: 0.6 + 0.4 * noise(id, 3))
        }
    }

    /// Deterministic 0…1 hash so every pulse id gets the same look each frame.
    private static func noise(_ id: Int, _ salt: Double) -> Double {
        let value = sin(Double(id) * 12.9898 + salt * 78.233) * 43_758.5453
        return value - value.rounded(.down)
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
