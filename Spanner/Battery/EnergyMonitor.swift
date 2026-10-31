import AppKit
import Darwin
import Observation
import SpannerCore

/// Power drawn by each app, from the kernel's per-process energy counter
/// (`proc_pid_rusage` → `ri_energy_nj`), grouped by app bundle.
///
/// Phase 2 measured that this works without root for every process the
/// person owns; root-owned daemons (WindowServer, kernel_task) return EPERM
/// and are left out, so totals cover apps, not the whole system.
@Observable
final class EnergyMonitor {
    private(set) var apps: [AppPower] = []
    private(set) var lastSample: Date?

    /// Set by the dashboard while it is on screen.
    var isVisible = false {
        didSet { if isVisible != oldValue { schedule() } }
    }

    @ObservationIgnored private let sampler = EnergySampler()
    @ObservationIgnored private var accumulator = EnergyAccumulator()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false

    private static let visibleInterval: Duration = .seconds(3)
    private static let backgroundInterval: Duration = .seconds(20)

    func start() {
        guard !isRunning else { return }
        isRunning = true
        schedule()
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    private func schedule() {
        guard isRunning else { return }
        task?.cancel()
        task = Task { [weak self, sampler] in
            while !Task.isCancelled {
                let samples = await Task.detached { sampler.sample() }.value
                guard let self, !Task.isCancelled else { return }
                let result = self.accumulator.update(samples, at: ProcessInfo.processInfo.systemUptime)
                if !result.isEmpty {
                    self.apps = result
                    self.lastSample = .now
                }
                try? await Task.sleep(for: self.isVisible ? Self.visibleInterval : Self.backgroundInterval)
            }
        }
    }
}

/// Reads the energy counter of every readable process. Used from one task
/// at a time, so its path cache needs no lock.
private nonisolated final class EnergySampler: @unchecked Sendable {
    private nonisolated(unsafe) var names: [pid_t: (key: String, name: String)] = [:]

    nonisolated init() {}

    nonisolated func sample() -> [ProcessEnergySample] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: max(capacity, 64))
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        let live = Set(pids.prefix(count))
        names = names.filter { live.contains($0.key) }

        var samples: [ProcessEnergySample] = []
        samples.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard status == 0 else { continue }
            let identity = names[pid] ?? identify(pid)
            names[pid] = identity
            samples.append(ProcessEnergySample(pid: pid, energyNanojoules: info.ri_energy_nj,
                                               groupKey: identity.key, name: identity.name))
        }
        return samples
    }

    private nonisolated func identify(_ pid: pid_t) -> (key: String, name: String) {
        guard let path = ProcessPath.executable(of: pid) else { return ("pid:\(pid)", "PID \(pid)") }
        if let app = AppBundlePath.outermostApp(in: path) {
            let name = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
            return (app, name)
        }
        let name = (path as NSString).lastPathComponent
        return (path, name)
    }
}
