import AppKit
import SpannerCore
import SwiftUI

// Cards for the System page's activity beyond processor and memory. Each
// reads only its own monitor properties and passes plain values down.

// MARK: - Network

struct NetworkCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let status = system.network
        let link = system.networkLink
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle(title: "Network", symbol: "network")
                    Spacer()
                    if case .connected(let interface) = link {
                        let label = [interface.displayName ?? interface.name, interface.ipv4].compactMap { $0 }
                            .joined(separator: " · ")
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if link == .disconnected || status?.sourceCount == 0 {
                    Text("No active network connection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    TransferTiles(status: status,
                                  inbound: .init(rateTitle: "Download", totalTitle: "Received",
                                                 symbol: "arrow.down", tint: SystemStyle.received),
                                  outbound: .init(rateTitle: "Upload", totalTitle: "Sent",
                                                  symbol: "arrow.up", tint: SystemStyle.sent))
                    RateChart(inbound: .init(title: "Download", history: system.downloadHistory, tint: SystemStyle.received),
                              outbound: .init(title: "Upload", history: system.uploadHistory, tint: SystemStyle.sent))
                }
            }
        }
    }
}

/// Rates and since-startup totals in both directions, shared by the Network
/// and Disk cards.
private struct TransferTiles: View {
    struct Direction {
        let rateTitle: String
        let totalTitle: String
        let symbol: String
        let tint: Color
    }

    let status: TransferStatus?
    let inbound: Direction
    let outbound: Direction

    var body: some View {
        TileRow {
            StatTile(title: inbound.rateTitle, value: status?.rates.map { SpannerFormat.rate($0.inbound) } ?? "–",
                     symbol: inbound.symbol, tint: inbound.tint)
            StatTile(title: outbound.rateTitle, value: status?.rates.map { SpannerFormat.rate($0.outbound) } ?? "–",
                     symbol: outbound.symbol, tint: outbound.tint)
            StatTile(title: inbound.totalTitle, value: status.map { SpannerFormat.bytes($0.totals.inbound) } ?? "–",
                     detail: "Since startup")
            StatTile(title: outbound.totalTitle, value: status.map { SpannerFormat.bytes($0.totals.outbound) } ?? "–",
                     detail: "Since startup")
        }
    }
}

// MARK: - Disk

struct DiskCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CardTitle(title: "Disk", symbol: "internaldrive")
                TransferTiles(status: system.disk,
                              inbound: .init(rateTitle: "Read", totalTitle: "Read", symbol: "arrow.down.doc",
                                             tint: SystemStyle.read),
                              outbound: .init(rateTitle: "Write", totalTitle: "Written", symbol: "arrow.up.doc",
                                              tint: SystemStyle.written))
                RateChart(inbound: .init(title: "Read", history: system.diskReadHistory, tint: SystemStyle.read),
                          outbound: .init(title: "Write", history: system.diskWriteHistory, tint: SystemStyle.written))
                VolumeList(volumes: system.volumes)
            }
        }
    }
}

private struct VolumeList: View {
    let volumes: [VolumeUsage]?

    var body: some View {
        if let volumes, !volumes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume)
                }
            }
            // Only a volume mounting or ejecting animates, not new figures.
            .animation(.spanner, value: volumes.map(\.id))
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeUsage

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    // The numbers matter more than a long name: the name
                    // truncates first.
                    Text("\(SpannerFormat.bytes(volume.available)) available of \(SpannerFormat.bytes(volume.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
                StackedBar(segments: [StackedBar.Segment(id: "used", value: Double(volume.used),
                                                         color: SystemStyle.tint(load: volume.fraction, base: SystemStyle.disk))],
                           total: Double(volume.total), height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(volume.name)
        .accessibilityValue("\(SpannerFormat.percent(volume.fraction)) used, \(SpannerFormat.bytes(volume.available)) available of \(SpannerFormat.bytes(volume.total))")
    }
}

// MARK: - Top processes

struct TopProcessesCard: View {
    @Environment(SystemMonitor.self) private var system
    @State private var metric = Metric.cpu

    enum Metric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        var id: Self { self }
    }

    var body: some View {
        let ranking = system.processes
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        CardTitle(title: "Top processes", symbol: "list.number")
                        Text("Your apps and processes. macOS's own background processes aren't included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.m)
                    Picker("Sort by", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                ProcessRows(rows: metric == .cpu ? ranking?.byCPU : ranking?.byMemory, metric: metric,
                            isMeasuring: ranking == nil || (metric == .cpu && ranking?.byCPU == nil))
            }
        }
    }
}

private struct ProcessRows: View {
    let rows: [ProcessUsage]?
    let metric: TopProcessesCard.Metric
    let isMeasuring: Bool

    var body: some View {
        if let rows, !rows.isEmpty {
            let peak = max(rows.map(value).max() ?? 0, .leastNonzeroMagnitude)
            // Not animated: rows re-rank every few seconds, and sliding them
            // would keep the page rendering for most of each interval.
            VStack(spacing: Spacing.s) {
                ForEach(rows) { row in
                    ProcessRow(row: row, value: text(for: row), fraction: value(row) / peak)
                }
            }
        } else {
            Text(isMeasuring ? "Measuring…" : "No processes to show.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func value(_ row: ProcessUsage) -> Double {
        metric == .cpu ? row.cpu : Double(row.memory)
    }

    private func text(for row: ProcessUsage) -> String {
        metric == .cpu ? SpannerFormat.processCPU(row.cpu) : SpannerFormat.memory(row.memory)
    }
}

private struct ProcessRow: View {
    let row: ProcessUsage
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: Spacing.m) {
            Group {
                if row.isApp {
                    Image(nsImage: AppIcons.icon(forBundle: row.groupKey))
                        .resizable()
                } else {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Spacing.s)
                    Text(value)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .fixedSize()
                }
                StackedBar(segments: [StackedBar.Segment(id: "value", value: fraction, color: .accentColor)],
                           total: 1, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(value)
    }
}

/// App icons by bundle path. `NSWorkspace` looks each one up through
/// IconServices, so rows that re-render every few seconds reuse the image.
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    /// Enough for the apps a session sees; cleared rather than evicted
    /// one by one, since a miss only costs a lookup.
    private static let limit = 64

    static func icon(forBundle path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        if cache.count >= limit { cache.removeAll() }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

// MARK: - About this Mac

/// Static facts, read once at launch.
struct SystemInfoCard: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let hardware = system.hardware
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardTitle(title: "This Mac", symbol: "info.circle")
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
                    row("Model", hardware.modelName)
                    row("Chip", hardware.cpuName)
                    row("Cores", CoreKind.summary(hardware.coreKinds)
                        ?? "\(ProcessInfo.processInfo.activeProcessorCount) cores")
                    row("Memory", "\(Int((Double(hardware.physicalMemory) / 1_073_741_824).rounded())) GB")
                    row("Graphics", hardware.gpuName)
                    row("Software", hardware.systemVersion)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
