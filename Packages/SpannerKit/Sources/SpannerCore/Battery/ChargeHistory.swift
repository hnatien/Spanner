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

    // MARK: - Chart and summary helpers

    /// Pauses in charging up to this long are treated as charging, so a brief
    /// stop (macOS pausing near full, a wobbly cable) doesn't split a session.
    public static let chargingGapTolerance: TimeInterval = 5 * 60

    /// Marks non-charging stretches between two charging samples as charging
    /// when they last at most `tolerance`.
    public static func bridgingChargingGaps(in samples: [ChargeSample],
                                            tolerance: TimeInterval = chargingGapTolerance) -> [ChargeSample] {
        var result = samples
        var lastCharging: Int?
        for index in result.indices where result[index].isCharging {
            if let previous = lastCharging, index - previous > 1,
               result[index].date.timeIntervalSince(result[previous].date) <= tolerance {
                for gap in (previous + 1)..<index { result[gap].isCharging = true }
            }
            lastCharging = index
        }
        return result
    }

    /// Thins samples for drawing. Percent is a whole number sampled each
    /// minute, so a raw line is a staircase; this keeps one point per level,
    /// at the middle of the stretch it held, which follows the real curve.
    /// Levels held longer than `holdThreshold` keep both ends so a genuinely
    /// flat stretch stays flat, and the first and last samples are kept so
    /// the line spans the whole window. Stretches split on charging changes.
    public static func smoothed(_ samples: [ChargeSample], holdThreshold: TimeInterval = 10 * 60) -> [ChargeSample] {
        guard let first = samples.first, let last = samples.last, samples.count > 2 else { return samples }
        var points: [ChargeSample] = [first]
        var start = 0
        for end in samples.indices {
            let isLastOfLevel = end == samples.count - 1
                || samples[end + 1].percent != samples[start].percent
                || samples[end + 1].isCharging != samples[start].isCharging
            guard isLastOfLevel else { continue }
            let head = samples[start], tail = samples[end]
            if tail.date.timeIntervalSince(head.date) > holdThreshold {
                points.append(head)
                points.append(tail)
            } else {
                var middle = head
                middle.date = head.date.addingTimeInterval(tail.date.timeIntervalSince(head.date) / 2)
                points.append(middle)
            }
            start = end + 1
        }
        points.append(last)
        // Drop duplicates where a kept end coincides with the first or last sample.
        var unique: [ChargeSample] = []
        for point in points where unique.last?.date != point.date {
            unique.append(point)
        }
        return unique
    }

    /// Samples further apart than this mean nothing was recorded in
    /// between (the Mac slept or Spanner wasn't running).
    public static let missingDataThreshold: TimeInterval = 5 * 60

    /// Everything the chart draws: charging pauses bridged, each recorded
    /// stretch smoothed and split by charging state, and a `.noData`
    /// segment joining stretches across each hole in the recording. A
    /// stretch after a hole settles its first moments (`settlingStart`).
    public static func chartSegments(for samples: [ChargeSample]) -> [ChargeSegment] {
        var blocks: [[ChargeSample]] = []
        for sample in bridgingChargingGaps(in: samples) {
            if let last = blocks.last?.last,
               sample.date.timeIntervalSince(last.date) <= missingDataThreshold {
                blocks[blocks.count - 1].append(sample)
            } else {
                blocks.append([sample])
            }
        }
        var result: [ChargeSegment] = []
        for block in blocks {
            guard let previous = result.last?.samples.last, let first = block.first else {
                result += segments(of: smoothed(block))
                continue
            }
            result.append(ChargeSegment(kind: .noData, samples: [previous, first]))
            result += segments(of: smoothed(settlingStart(of: block)))
        }
        return result
    }

    /// The first samples after a hole can report a state macOS is about to
    /// change (charging resumes a minute after wake), so a state held for at
    /// most `settleTime` at the start of a stretch takes the state that follows.
    static func settlingStart(of block: [ChargeSample], settleTime: TimeInterval = 2 * 60) -> [ChargeSample] {
        guard let first = block.first,
              let flip = block.firstIndex(where: { $0.isCharging != first.isCharging }),
              block[flip].date.timeIntervalSince(first.date) <= settleTime else { return block }
        var result = block
        for index in 0..<flip { result[index].isCharging = block[flip].isCharging }
        return result
    }

    /// Consecutive samples sharing a charging state. Each segment after the
    /// first starts with the previous segment's last sample, so lines drawn
    /// per segment join up.
    public static func segments(of samples: [ChargeSample]) -> [ChargeSegment] {
        var segments: [ChargeSegment] = []
        for sample in samples {
            let kind: ChargeSegment.Kind = sample.isCharging ? .charging : .notCharging
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].samples.append(sample)
            } else {
                let joint = segments.last?.samples.last
                segments.append(ChargeSegment(kind: kind, samples: (joint.map { [$0] } ?? []) + [sample]))
            }
        }
        return segments
    }

    /// How fast the charge is moving in the current charging or
    /// non-charging stretch, measured over at most its last `window`
    /// seconds. Nil until the stretch spans `minimumSpan`, because whole
    /// percent steps make shorter measurements jumpy.
    public func currentTrend(window: TimeInterval = 60 * 60,
                             minimumSpan: TimeInterval = 15 * 60) -> ChargeTrend? {
        let bridged = Self.bridgingChargingGaps(in: samples)
        guard let last = bridged.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-window)
        var first = last
        for sample in bridged.reversed() {
            guard sample.isCharging == last.isCharging, sample.date >= cutoff else { break }
            first = sample
        }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= minimumSpan else { return nil }
        return ChargeTrend(isCharging: last.isCharging,
                           percentPerHour: Double(last.percent - first.percent) / (span / 3600),
                           span: span)
    }

    /// The most recent charging session in the history, with brief pauses
    /// bridged. It ends at the unplug sample, or is ongoing if the latest
    /// sample is still charging.
    public var lastChargeSession: ChargeSession? {
        let bridged = Self.bridgingChargingGaps(in: samples)
        guard let lastCharging = bridged.lastIndex(where: \.isCharging) else { return nil }
        var startIndex = lastCharging
        while startIndex > 0, bridged[startIndex - 1].isCharging { startIndex -= 1 }
        let isOngoing = lastCharging == bridged.count - 1
        let end = isOngoing ? bridged[lastCharging] : bridged[lastCharging + 1]
        return ChargeSession(start: bridged[startIndex].date, end: end.date,
                             fromPercent: bridged[startIndex].percent, toPercent: end.percent,
                             isOngoing: isOngoing)
    }
}

/// A run of samples drawn in one style.
public struct ChargeSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case charging, notCharging
        /// Nothing was recorded between the two samples.
        case noData
    }

    public var kind: Kind
    public var samples: [ChargeSample]
}

/// Rate of change of the charge. Negative while draining.
public struct ChargeTrend: Equatable, Sendable {
    public var isCharging: Bool
    public var percentPerHour: Double
    /// How much time the rate was measured over.
    public var span: TimeInterval
}

/// One charging session, plug-in to unplug.
public struct ChargeSession: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var fromPercent: Int
    public var toPercent: Int
    public var isOngoing: Bool

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
