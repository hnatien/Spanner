import Foundation

/// Groups helper processes under the app they belong to, by executable path.
public enum AppBundlePath {
    /// The outermost `.app` bundle containing `path`, so a browser's helper
    /// apps (`Chrome.app/Contents/Frameworks/…/Helper.app/…`) count toward
    /// the browser. Nil for processes outside any app bundle.
    public static func outermostApp(in path: String) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            components.append(component)
            if component.hasSuffix(".app") {
                return components.joined(separator: "/")
            }
        }
        return nil
    }

    /// The app a process's energy counts toward: the bundle it lives in, or
    /// failing that the bundle of the process macOS holds responsible for it,
    /// so shared XPC services (WebKit's GPU and web content processes) count
    /// toward the app they serve. Bundles `isApp` rejects are skipped, so a
    /// tool packaged as an `.app` falls through to whoever launched it. Nil
    /// when neither is inside an app.
    public static func owningApp(executable: String, responsible: String?,
                                 isApp: (String) -> Bool) -> String? {
        [outermostApp(in: executable), responsible.flatMap(outermostApp(in:))]
            .compactMap { $0 }
            .first(where: isApp)
    }

    /// Whether the bundle at `path` is an app people use, from its
    /// Info.plist: false for background-only bundles (command-line tools
    /// packaged as apps) and for macOS's own agents that hide from the Dock
    /// (WindowManager, Control Center). Third-party menu bar apps stay apps.
    public static func isApp(at path: String, info: [String: Any]) -> Bool {
        if info["LSBackgroundOnly"] as? Bool == true { return false }
        if info["LSUIElement"] as? Bool == true, path.hasPrefix("/System/") { return false }
        return true
    }
}

/// One process's cumulative energy counter (`ri_energy_nj`) at a moment.
public struct ProcessEnergySample: Equatable, Sendable {
    public let pid: Int32
    public let energyNanojoules: UInt64
    /// What to group by: the outermost app bundle path, or the process name.
    public let groupKey: String
    public let name: String

    public init(pid: Int32, energyNanojoules: UInt64, groupKey: String, name: String) {
        self.pid = pid
        self.energyNanojoules = energyNanojoules
        self.groupKey = groupKey
        self.name = name
    }
}

/// Power drawn by one app (all its processes) over the last interval.
public struct AppPower: Identifiable, Equatable, Sendable {
    public var id: String { groupKey }
    public let groupKey: String
    public let name: String
    /// Average watts over the last sampling interval.
    public let watts: Double
    /// Energy since Spanner started measuring, in joules.
    public let joules: Double

    public init(groupKey: String, name: String, watts: Double, joules: Double) {
        self.groupKey = groupKey
        self.name = name
        self.watts = watts
        self.joules = joules
    }

    /// False for processes outside any app bundle, grouped by their own path.
    public var isApp: Bool { groupKey.hasSuffix(".app") }
}

/// Processes no app accounts for (background agents and daemons, tools
/// started outside an app), summed into one row.
public struct BackgroundPower: Equatable, Sendable {
    public let watts: Double
    public let joules: Double
    /// Process names, busiest first.
    public let names: [String]

    /// Sums the non-app entries of `ranked`; nil when there are none.
    public init?(_ ranked: [AppPower]) {
        let processes = ranked.filter { !$0.isApp }
        guard !processes.isEmpty else { return nil }
        watts = processes.reduce(0) { $0 + $1.watts }
        joules = processes.reduce(0) { $0 + $1.joules }
        names = processes.map(\.name)
    }
}

/// Turns successive energy samples into per-app power.
///
/// Counters are cumulative per process, so power is the difference between
/// two samples. New processes and reused PIDs whose counter went backwards
/// contribute nothing until their second sample.
public struct EnergyAccumulator: Sendable {
    private var previous: [Int32: UInt64] = [:]
    private var lastTime: TimeInterval?
    private var totals: [String: Double] = [:]
    private var names: [String: String] = [:]

    public init() {}

    public mutating func update(_ samples: [ProcessEnergySample], at time: TimeInterval) -> [AppPower] {
        defer {
            previous = Dictionary(samples.map { ($0.pid, $0.energyNanojoules) }, uniquingKeysWith: max)
            lastTime = time
        }
        guard let lastTime, time > lastTime else { return [] }
        let interval = time - lastTime
        var intervalJoules: [String: Double] = [:]
        for sample in samples {
            names[sample.groupKey] = names[sample.groupKey] ?? sample.name
            guard let before = previous[sample.pid], sample.energyNanojoules >= before else { continue }
            intervalJoules[sample.groupKey, default: 0] += Double(sample.energyNanojoules - before) / 1e9
        }
        for (key, joules) in intervalJoules {
            totals[key, default: 0] += joules
        }
        return intervalJoules
            .map { key, joules in
                AppPower(groupKey: key, name: names[key] ?? key, watts: joules / interval, joules: totals[key] ?? joules)
            }
            .sorted { $0.watts == $1.watts ? $0.name < $1.name : $0.watts > $1.watts }
    }
}
