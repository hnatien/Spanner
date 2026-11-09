import Darwin
import Foundation
import SpannerCore

/// Executable path of a running process, via `proc_pidpath`.
nonisolated enum ProcessPath {
    static func executable(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}

/// Names a process by the app it belongs to or works for, as the energy and
/// process lists group them. Caches each answer per process (pid plus start
/// time, so a reused pid is identified afresh) and per bundle. Used from one
/// task at a time, so the caches need no lock.
nonisolated final class ProcessIdentifier {
    /// What to group by (the owning app bundle path, or the executable
    /// path) and the name to show.
    struct Identity: Sendable {
        let key: String
        let name: String
    }

    private struct Process: Hashable {
        let pid: pid_t
        let startTime: UInt64
    }

    private var identities: [Process: Identity] = [:]
    /// Processes identified during the current pass; replaces `identities`
    /// at the end, so processes that exited drop out.
    private var seen: [Process: Identity] = [:]
    /// Whether each bundle seen so far counts as an app, by bundle path.
    private var bundles: [String: Bool] = [:]

    func identity(of pid: pid_t, startTime: UInt64) -> Identity {
        let process = Process(pid: pid, startTime: startTime)
        let identity = identities[process] ?? identify(pid)
        seen[process] = identity
        return identity
    }

    /// Ends a pass over every process: forgets the ones not seen in it.
    func endPass() {
        identities = seen
        seen = [:]
        seen.reserveCapacity(identities.count)
    }

    private func identify(_ pid: pid_t) -> Identity {
        guard let path = ProcessPath.executable(of: pid) else { return Identity(key: "pid:\(pid)", name: "PID \(pid)") }
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        let responsiblePath = responsible > 0 && responsible != pid ? ProcessPath.executable(of: responsible) : nil
        if let app = AppBundlePath.owningApp(executable: path, responsible: responsiblePath, isApp: isApp) {
            let name = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
            return Identity(key: app, name: name)
        }
        return Identity(key: path, name: (path as NSString).lastPathComponent)
    }

    /// Bundles whose Info.plist can't be read count as apps.
    private func isApp(_ bundle: String) -> Bool {
        if let known = bundles[bundle] { return known }
        let info = NSDictionary(contentsOf: URL(fileURLWithPath: bundle).appending(path: "Contents/Info.plist"))
        let result = (info as? [String: Any]).map { AppBundlePath.isApp(at: bundle, info: $0) } ?? true
        bundles[bundle] = result
        return result
    }
}
