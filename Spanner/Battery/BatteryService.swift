import Foundation
import IOKit.ps
import Observation
import OSLog
import SpannerCore

/// Live battery state for the dashboard and menu bar.
///
/// Updates come from two sources: an IOPowerSources run-loop notification
/// (instant, on plug/unplug and percentage changes) and a poll of the
/// registry for values that change continuously (watts, amps, temperature).
/// The poll is fast only while battery UI is on screen.
@Observable
final class BatteryService {
    private(set) var snapshot: BatterySnapshot?
    /// False on Macs without a battery; nil until the first read.
    private(set) var hasBattery: Bool?
    private(set) var history = ChargeHistory()
    private(set) var accessories: [AccessoryBattery] = []

    /// Set by the menu bar panel while it is open.
    var isDetailedRefresh = false {
        didSet { detailChanged(from: oldValue || isDashboardVisible) }
    }

    /// Set by the dashboard page while it is on screen. Kept separate from
    /// `isDetailedRefresh` so closing one surface doesn't slow the other.
    var isDashboardVisible = false {
        didSet { detailChanged(from: isDetailedRefresh || oldValue) }
    }

    private var wantsDetail: Bool { isDetailedRefresh || isDashboardVisible }

    var flow: PowerFlow? { snapshot.map(PowerFlow.init(snapshot:)) }

    @ObservationIgnored private let reader = BatteryReader()
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var accessoryTask: Task<Void, Never>?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var lastHistorySave = Date.distantPast

    private static let detailedInterval: Duration = .seconds(2)
    private static let backgroundInterval: Duration = .seconds(30)
    private static let accessoryInterval: Duration = .seconds(60)
    private static let historySaveInterval: TimeInterval = 10 * 60
    private static let log = Logger(subsystem: "dev.spanner.Spanner", category: "Battery")

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reader.open()
        history = Self.loadHistory()
        refresh()
        subscribeToPowerSourceChanges()
        schedulePolling()
        accessoryTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.accessories = BatteryReader.accessories()
                try? await Task.sleep(for: Self.accessoryInterval)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTask?.cancel()
        accessoryTask?.cancel()
        pollTask = nil
        accessoryTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        reader.close()
        saveHistory()
    }

    func refresh() {
        let snapshot = reader.snapshot()
        hasBattery = snapshot != nil
        if snapshot != self.snapshot {
            self.snapshot = snapshot
        }
        guard let snapshot else { return }

        let sample = ChargeSample(date: .now, percent: snapshot.percent, isCharging: snapshot.isCharging,
                                  systemWatts: PowerFlow(snapshot: snapshot).systemWatts)
        if history.record(sample), Date.now.timeIntervalSince(lastHistorySave) > Self.historySaveInterval {
            saveHistory()
        }
    }

    private func detailChanged(from previous: Bool) {
        guard wantsDetail != previous, isRunning else { return }
        if wantsDetail { refresh() }
        schedulePolling()
    }

    private func schedulePolling() {
        pollTask?.cancel()
        let interval = wantsDetail ? Self.detailedInterval : Self.backgroundInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func subscribeToPowerSourceChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        // C callback: delivered on the main run loop, so hopping into the
        // main actor is safe. The service lives for the whole app session.
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Self.log.error("IOPSNotificationCreateRunLoopSource failed; relying on polling")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    // MARK: History persistence

    private static var historyURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Spanner", directoryHint: .isDirectory)
            .appending(path: "battery-history.json")
    }

    private static func loadHistory() -> ChargeHistory {
        guard let data = try? Data(contentsOf: historyURL) else { return ChargeHistory() }
        do {
            var history = try JSONDecoder().decode(ChargeHistory.self, from: data)
            history.trim(now: .now)
            return history
        } catch {
            log.error("Discarding unreadable battery history: \(error.localizedDescription)")
            return ChargeHistory()
        }
    }

    private func saveHistory() {
        lastHistorySave = .now
        let url = Self.historyURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Could not save battery history: \(error.localizedDescription)")
        }
    }
}
