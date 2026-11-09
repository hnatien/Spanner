import SpannerCore
import SwiftUI

/// CPU, GPU and memory gauges side by side for the menu bar panel. The
/// panel opens the System page when it's clicked.
struct SystemMenuSummary: View {
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let snapshot = system.snapshot
        HStack(alignment: .top, spacing: Spacing.s) {
            gauge(title: "CPU", fraction: snapshot?.cpu?.total,
                  tint: SystemStyle.tint(load: snapshot?.cpu?.total ?? 0, base: SystemStyle.cpu),
                  detail: coresDetail)
            if system.hardware.gpuName != nil {
                gauge(title: "GPU", fraction: snapshot?.gpu?.utilization,
                      tint: SystemStyle.tint(load: snapshot?.gpu?.utilization ?? 0, base: SystemStyle.gpu),
                      detail: snapshot?.gpu?.memoryInUse.map(SpannerFormat.memory) ?? " ")
            }
            gauge(title: "Memory", fraction: snapshot?.memory?.fraction,
                  tint: SystemStyle.tint(for: snapshot?.memory?.pressure ?? .normal),
                  detail: memoryDetail(snapshot?.memory))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxHeight: 46)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the System page")
        .onAppear { system.isPanelVisible = true }
        .onDisappear { system.isPanelVisible = false }
    }

    private var coresDetail: String {
        let count = system.hardware.coreKinds.count
        return count > 0 ? "\(count) cores" : "\(ProcessInfo.processInfo.activeProcessorCount) cores"
    }

    private func memoryDetail(_ memory: MemoryUsage?) -> String {
        guard let memory else { return " " }
        return "\(SpannerFormat.memory(memory.used)) of \(SpannerFormat.memory(memory.total))"
    }

    private func gauge(title: String, fraction: Double?, tint: Color, detail: String) -> some View {
        VStack(spacing: Spacing.xs) {
            LoadRing(fraction: fraction, tint: tint, size: 46)
            VStack(spacing: 0) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(fraction.map { "\(SpannerFormat.percent($0)), \(detail)" } ?? "Measuring")
    }
}
