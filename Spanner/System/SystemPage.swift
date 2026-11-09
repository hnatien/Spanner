import Charts
import SpannerCore
import SwiftUI

/// Main-window page with live processor, graphics, memory, network and
/// disk activity, the busiest apps, and facts about this Mac.
///
/// Each card reads only the monitor properties it shows, so a new network
/// rate redraws the Network card and nothing else. This body reads nothing
/// that changes.
struct SystemPage: View {
    @Environment(SystemMonitor.self) private var system
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Page {
            PageHeader(title: "System",
                       subtitle: "Processor, memory, network and disk activity, updated live while this page is open.",
                       symbol: AppSection.system.symbol, tint: FeatureTint.system) {
                ThermalBadge()
            }

            OverviewCard()
            ProcessorCard()
            if system.hardware.gpuName != nil {
                GraphicsCard()
            }
            MemoryCard()
            NetworkCard()
            DiskCard()
            TopProcessesCard()
            SystemInfoCard()
        }
        // Sample only while the window is in the active app, like the battery
        // dashboard: a page left open behind other windows costs nothing.
        .onAppear { system.isPageVisible = appearsActive }
        .onChange(of: appearsActive) { _, active in system.isPageVisible = active }
        .onDisappear { system.isPageVisible = false }
    }
}

/// macOS's thermal state. Pushed by the system (the monitor observes its
/// notification), so it costs nothing until it changes.
private struct ThermalBadge: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        if let state = system.thermalState {
            StatusPill(text: SystemStyle.label(for: state), symbol: SystemStyle.symbol(for: state),
                       tint: SystemStyle.tint(for: state))
                .help("How hard macOS is working to keep the Mac cool. Serious and Critical slow the chip down.")
                .animation(.spanner, value: state)
        }
    }
}

// MARK: - Overview

private struct OverviewCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let snapshot = system.snapshot
        Card(padding: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.l) {
                gauge(title: "Processor", fraction: snapshot?.cpu?.total,
                      tint: SystemStyle.tint(load: snapshot?.cpu?.total ?? 0, base: SystemStyle.cpu),
                      detail: system.hardware.cpuName ?? "CPU")
                if let gpuName = system.hardware.gpuName {
                    gauge(title: "Graphics", fraction: snapshot?.gpu?.utilization,
                          tint: SystemStyle.tint(load: snapshot?.gpu?.utilization ?? 0, base: SystemStyle.gpu),
                          detail: gpuName)
                }
                gauge(title: "Memory", fraction: snapshot?.memory?.fraction,
                      tint: SystemStyle.tint(for: snapshot?.memory?.pressure ?? .normal),
                      detail: snapshot?.memory.map { "\(SpannerFormat.memory($0.used)) of \(SpannerFormat.memory($0.total))" } ?? " ")
            }
        }
    }

    private func gauge(title: String, fraction: Double?, tint: Color, detail: String) -> some View {
        VStack(spacing: Spacing.s) {
            LoadRing(fraction: fraction, tint: tint, size: 88, animated: false)
            VStack(spacing: Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(fraction.map { "\(SpannerFormat.percent($0)), \(detail)" } ?? "Measuring")
    }
}

// MARK: - Processor

private struct ProcessorCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let cpu = system.cpu
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle(title: "Processor", symbol: "cpu")
                    Spacer()
                    if let summary = CoreKind.summary(system.hardware.coreKinds) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProcessorStats(user: cpu?.user, system: cpu?.system, load: system.loadAverage, uptime: system.uptime)
                LoadChart(history: system.cpuHistory, tint: SystemStyle.cpu)
                if let cores = cpu?.cores, !cores.isEmpty {
                    CoreBars(cores: cores, clusters: CoreKind.clusters(system.hardware.coreKinds))
                }
            }
        }
    }
}

/// User and system time, load average and uptime.
private struct ProcessorStats: View {
    let user: Double?
    let system: Double?
    let load: LoadAverage?
    let uptime: TimeInterval?

    var body: some View {
        TileRow {
            StatTile(title: "User", value: user.map(SpannerFormat.percent) ?? "–",
                     detail: "Apps' own code", symbol: "person.fill", tint: SystemStyle.cpu)
            StatTile(title: "System", value: system.map(SpannerFormat.percent) ?? "–",
                     detail: "macOS on their behalf", symbol: "gearshape.fill", tint: .orange)
            StatTile(title: "Load average", value: load?.formatted ?? "–", detail: "1, 5 and 15 minutes")
            StatTile(title: "Uptime", value: uptime.map(SpannerFormat.uptime) ?? "–", detail: "Since startup")
        }
    }
}

/// One vertical bar per logical core, grouped into clusters (Efficiency,
/// Performance and any newer kind) when the device tree says which is which.
private struct CoreBars: View {
    let cores: [Double]
    let clusters: [CoreCluster]

    private struct Group: Identifiable {
        let id: Int
        let title: String?
        let range: Range<Int>
    }

    private var groups: [Group] {
        // Clusters that don't describe every core would label the wrong bars.
        guard clusters.first?.range.lowerBound == 0, clusters.last?.range.upperBound == cores.count else {
            return [Group(id: 0, title: nil, range: cores.indices)]
        }
        return clusters.map { Group(id: $0.id, title: $0.kind.title, range: $0.range) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .bottom, spacing: Spacing.xs) {
                        // Core numbers are stable identities.
                        ForEach(group.range, id: \.self) { core in
                            CoreBar(load: cores[core])
                        }
                    }
                    .frame(height: 44)
                    if let title = group.title {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load per core")
        .accessibilityValue(cores.map(SpannerFormat.percent).joined(separator: ", "))
    }
}

private struct CoreBar: View {
    let load: Double

    var body: some View {
        // Fixed-size shapes scaled by the load: cheaper than a GeometryReader
        // re-laying out each bar every sample. No animation: ten springs
        // every two seconds kept the page rendering most of the time.
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(SystemStyle.tint(load: load, base: SystemStyle.cpu).gradient)
                    .scaleEffect(x: 1, y: max(0.08, load), anchor: .bottom)
            }
            .frame(width: 16)
    }
}

// MARK: - Graphics

private struct GraphicsCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle(title: "Graphics", symbol: "square.3.layers.3d")
                    Spacer()
                    if let memory = system.gpu?.memoryInUse {
                        Text("\(SpannerFormat.memory(memory)) in use")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                LoadChart(history: system.gpuHistory, tint: SystemStyle.gpu)
            }
        }
    }
}

// MARK: - Memory

private struct MemoryCard: View {
    @Environment(SystemMonitor.self) private var system

    private struct Segment: Identifiable {
        let id: String
        let bytes: UInt64
        let color: Color
        var title: String { id }
    }

    var body: some View {
        let memory = system.memory
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle(title: "Memory", symbol: "memorychip")
                    Spacer()
                    if let pressure = memory?.pressure {
                        StatusPill(text: "Pressure: \(SystemStyle.label(for: pressure))",
                                   symbol: pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                   tint: pressure == .normal ? .green : SystemStyle.tint(for: pressure))
                    }
                }
                if let memory {
                    breakdown(memory)
                }
                LoadChart(history: system.memoryHistory, tint: SystemStyle.memory)
            }
        }
    }

    private func breakdown(_ memory: MemoryUsage) -> some View {
        let segments = [
            Segment(id: "App", bytes: memory.app, color: SystemStyle.memory),
            Segment(id: "Wired", bytes: memory.wired, color: .orange),
            Segment(id: "Compressed", bytes: memory.compressed, color: .purple),
            Segment(id: "Cached", bytes: memory.cached, color: .gray),
        ]
        return VStack(alignment: .leading, spacing: Spacing.m) {
            StackedBar(segments: segments.map { StackedBar.Segment(id: $0.id, value: Double($0.bytes), color: $0.color) },
                       total: Double(memory.total))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.l, alignment: .topLeading)],
                      alignment: .leading, spacing: Spacing.m) {
                ForEach(segments) { segment in
                    legendItem(segment.title, value: SpannerFormat.memory(segment.bytes), color: segment.color)
                }
                legendItem("Swap", value: SpannerFormat.memory(memory.swapUsed), color: nil)
            }
        }
    }

    private func legendItem(_ title: String, value: String, color: Color?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Circle()
                .fill(color ?? .clear)
                .strokeBorder(color == nil ? Color.secondary : .clear, lineWidth: 1)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

/// The last two minutes of a 0...1 load as a filled line. Animations are
/// off: a new point every two seconds shifting the whole line is easier to
/// read, and much cheaper, without a transition.
private struct LoadChart: View {
    let history: MetricHistory
    let tint: Color

    var body: some View {
        Group {
            if history.count < 2 {
                Text("Collecting data…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Each sample keeps its id as the history scrolls, so the
                // chart diffs one new point per tick. The newest sample sits
                // at the right edge; older ones extend left.
                Chart(history.samples) { sample in
                    AreaMark(x: .value("Time", sample.id), y: .value("Load", sample.value))
                        .foregroundStyle(tint.opacity(0.18).gradient)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", sample.id), y: .value("Load", sample.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                .chartXScale(domain: history.idDomain)
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let load = value.as(Double.self) { Text(SpannerFormat.percent(load)) }
                        }
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last two minutes")
        .accessibilityValue(history.last.map { "Now \(SpannerFormat.percent($0))" } ?? "Collecting data")
    }
}
