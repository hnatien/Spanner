import Foundation

/// How long a keep-awake session lasts.
public enum KeepAwakeDuration: Hashable, Sendable, CaseIterable, Identifiable {
    case minutes15
    case minutes30
    case hour1
    case hours2
    case hours5
    case indefinitely

    public var id: Self { self }

    /// Length in seconds, or nil for a session that runs until stopped.
    public var interval: TimeInterval? {
        switch self {
        case .minutes15: 15 * 60
        case .minutes30: 30 * 60
        case .hour1: 60 * 60
        case .hours2: 2 * 60 * 60
        case .hours5: 5 * 60 * 60
        case .indefinitely: nil
        }
    }

    public var title: String {
        switch self {
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .hour1: "1 hour"
        case .hours2: "2 hours"
        case .hours5: "5 hours"
        case .indefinitely: "Until turned off"
        }
    }
}

/// An active keep-awake session. Pure value: the controller owns the power
/// assertion, this type only answers time questions so it can be tested.
public struct KeepAwakeSession: Equatable, Sendable {
    public let start: Date
    public let end: Date?
    public let keepsDisplayOn: Bool

    public init(duration: KeepAwakeDuration, keepsDisplayOn: Bool, now: Date) {
        start = now
        end = duration.interval.map { now.addingTimeInterval($0) }
        self.keepsDisplayOn = keepsDisplayOn
    }

    /// Seconds left, never negative; nil for an indefinite session.
    public func remaining(at now: Date) -> TimeInterval? {
        end.map { max(0, $0.timeIntervalSince(now)) }
    }

    public func isExpired(at now: Date) -> Bool {
        guard let end else { return false }
        return now >= end
    }

    /// Fraction of the session elapsed (0...1); nil for an indefinite session.
    public func progress(at now: Date) -> Double? {
        guard let end else { return nil }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}
