import Darwin
import Foundation
import SpannerCore

/// CPU and memory of every readable process, grouped by app the way the
/// energy list groups them (`ProcessIdentifier`).
///
/// One `proc_pid_rusage` call per process, no spawning of `ps` or `top`.
/// Processes owned by root or other users return EPERM and are left out, and
/// processes that exit between listing and reading return ESRCH; both are
/// skipped quietly, so totals cover the person's own apps. Used from one
/// task at a time.
nonisolated final class ProcessReader: @unchecked Sendable {
    private let identifier = ProcessIdentifier()
    private nonisolated(unsafe) var tracker: ProcessTracker
    /// Reused between reads: a Mac runs several hundred processes.
    private nonisolated(unsafe) var pids: [pid_t] = []

    nonisolated init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        tracker = ProcessTracker(timebaseNumer: timebase.numer, timebaseDenom: timebase.denom)
    }

    nonisolated func resetBaseline() {
        tracker.reset()
    }

    /// The top `limit` apps by CPU and by memory; nil when processes can't
    /// be listed.
    nonisolated func read(limit: Int) -> ProcessRanking? {
        let needed = Int(proc_listallpids(nil, 0))
        guard needed > 0 else { return nil }
        if pids.count < needed + 64 { pids = [pid_t](repeating: 0, count: needed + 128) }
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return nil }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(count)
        for pid in pids.prefix(min(count, pids.count)) where pid > 0 {
            var info = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard status == 0 else { continue }
            let identity = identifier.identity(of: pid, startTime: info.ri_proc_start_abstime)
            samples.append(ProcessSample(pid: pid, startTime: info.ri_proc_start_abstime,
                                         cpuTime: info.ri_user_time &+ info.ri_system_time,
                                         footprint: info.ri_phys_footprint,
                                         groupKey: identity.key, name: identity.name))
        }
        identifier.endPass()
        return tracker.update(samples, at: ProcessInfo.processInfo.systemUptime, limit: limit)
    }
}
