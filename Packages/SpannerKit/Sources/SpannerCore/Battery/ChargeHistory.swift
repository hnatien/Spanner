import Foundation

/// One history point.
public struct ChargeSample: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    public var percent: Int
    public var isCharging: Bool
    /// What the Mac was drawing, in watts, when known.
    public var systemWatts: Double?

    public var id: Date { date }

    public init(date: Date, percent: Int, isCharging: Bool, systemWatts: Double? = nil) {
        self.date = date
        self.percent = percent
        self.isCharging = isCharging
        self.systemWatts = systemWatts
    }
}

/// Rolling 24-hour charge history at roughly one sample per minute
/// (at most 1,440 points), persisted as JSON between launches.
public struct ChargeHistory: Codable, Equatable, Sendable {
    public private(set) var samples: [ChargeSample] = []

    public static let retention: TimeInterval = 24 * 60 * 60
    public static let interval: TimeInterval = 60

    public init(samples: [ChargeSample] = []) {
        self.samples = samples.sorted { $0.date < $1.date }
    }

    /// Adds a sample if a minute has passed since the last one, or the
    /// charging state flipped (so plug/unplug moments are never lost), then
    /// drops samples older than 24 hours. Returns whether it was added.
    @discardableResult
    public mutating func record(_ sample: ChargeSample) -> Bool {
        if let last = samples.last {
            let elapsed = sample.date.timeIntervalSince(last.date)
            guard elapsed >= 0 else { return false }
            guard elapsed >= Self.interval || sample.isCharging != last.isCharging else { return false }
        }
        samples.append(sample)
        trim(now: sample.date)
        return true
    }

    public mutating func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }) {
            if firstKept > 0 { samples.removeFirst(firstKept) }
        } else {
            samples.removeAll()
        }
    }

    /// Samples within the last `window` seconds before `now`.
    public func samples(within window: TimeInterval, now: Date) -> [ChargeSample] {
        let cutoff = now.addingTimeInterval(-window)
        return samples.filter { $0.date >= cutoff && $0.date <= now }
    }

    /// Contiguous stretches where the Mac was charging, for chart shading.
    /// A run lasts until the first non-charging sample (the unplug moment),
    /// or the last sample if it is still charging.
    public static func chargingRuns(in samples: [ChargeSample]) -> [ClosedRange<Date>] {
        var runs: [ClosedRange<Date>] = []
        var start: Date?
        for sample in samples {
            if sample.isCharging {
                if start == nil { start = sample.date }
            } else if let runStart = start {
                runs.append(runStart...sample.date)
                start = nil
            }
        }
        if let runStart = start, let last = samples.last {
            runs.append(runStart...last.date)
        }
        return runs
    }
}
