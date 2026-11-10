import AppKit
import Foundation
import Observation
import SpannerCore

/// Live system activity for the menu bar panel and System page.
///
/// Samples only while one of those is on screen and does nothing at all
/// otherwise: unlike battery history, a load reading nobody sees has no use
/// later. The panel needs only processor, graphics and memory; network,
/// disk, processes, load and thermal state are sampled only while the page
/// is visible.
///
/// Each source runs at its own cadence, one task per cadence (see the
/// intervals below), and every reading is a separate observed property, so
/// a view redraws only when something it shows changes: a new network rate
/// doesn't touch the Memory card. Values are rounded to what's displayed
/// before they're compared, so an idle Mac doesn't redraw anything.
@Observable
final class SystemMonitor: FeatureModule {
    // Processor, graphics and memory (the panel and the page).
    private(set) var cpu: CPULoad?
    private(set) var gpu: GPUUsage?
    private(set) var memory: MemoryUsage?
    private(set) var cpuHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var gpuHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var memoryHistory = MetricHistory(capacity: SystemMonitor.historyLength)

    // Page only.
    private(set) var loadAverage: LoadAverage?
    /// Time since startup, in whole minutes.
    private(set) var uptime: TimeInterval?
    private(set) var thermalState: ProcessInfo.ThermalState?
    private(set) var network: TransferStatus?
    private(set) var networkLink = NetworkLink.unknown
    private(set) var downloadHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var uploadHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var disk: TransferStatus?
    private(set) var volumes: [VolumeUsage]?
    private(set) var diskReadHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var diskWriteHistory = MetricHistory(capacity: SystemMonitor.historyLength)
    private(set) var processes: ProcessRanking?

    /// Processor, graphics and memory as one value, for the menu bar tile.
    var snapshot: SystemSnapshot? {
        guard cpu != nil || memory != nil || gpu != nil else { return nil }
        return SystemSnapshot(cpu: cpu, memory: memory, gpu: gpu)
    }

    /// Set by the menu bar panel's System tile while it is on screen.
    var isPanelVisible = false {
        didSet { if isPanelVisible != oldValue { schedule() } }
    }

    /// Set by the System page while it is on screen in the active app.
    var isPageVisible = false {
        didSet { if isPageVisible != oldValue { schedule() } }
    }

    let hardware: SystemReader.Hardware

    @ObservationIgnored private let reader = SystemReader()
    @ObservationIgnored private let networkReader = NetworkReader()
    @ObservationIgnored private let diskReader = DiskReader()
    @ObservationIgnored private let processReader = ProcessReader()

    /// One task per cadence. A replacement waits for the task it replaces
    /// to finish its current read, so a reader is never used by two at once.
    @ObservationIgnored private var fastTask: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var capacityTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    @ObservationIgnored private var lastSample = Date.distantPast
    /// Network and disk are read only for the page, so their baselines age
    /// separately from the panel's processor readings.
    @ObservationIgnored private var lastTransferSample = Date.distantPast
    @ObservationIgnored private var lastHistorySample = Date.distantPast
    @ObservationIgnored private var lastProcessSample = Date.distantPast
    /// Counted interfaces at the last read, to notice one coming or going.
    @ObservationIgnored private var lastInterfaces: [String]?
    /// Set when volumes mount or unmount, so the next disk read matches the
    /// drives again.
    @ObservationIgnored private var drivesChanged = false

    /// Processor, graphics, memory, network and disk rates.
    static let interval: Duration = .seconds(2)
    private static let processInterval: Duration = .seconds(3)
    /// Load average and uptime.
    private static let statusInterval: Duration = .seconds(5)
    /// Volume capacity and the network interface label, which change
    /// rarely; mounts, unmounts and interface changes refresh them early.
    private static let capacityInterval: Duration = .seconds(30)
    /// Two minutes of history at one sample every two seconds.
    static let historyLength = 60
    /// Rows in the top processes card.
    static let processLimit = 6
    /// Load and rates need two readings; the first one shows after this
    /// delay instead of a full interval, so the page fills in almost at once.
    private static let firstFastDelay: Duration = .milliseconds(500)
    private static let firstProcessDelay: Duration = .seconds(1)
    /// Longest pause, in seconds, that history and rate baselines span.
    private static let maxGap: TimeInterval = 6

    init() {
        hardware = reader.hardware
    }

    func stop() {
        isPanelVisible = false
        isPageVisible = false
    }

    // MARK: Scheduling

    private func schedule() {
        let page = isPageVisible
        fastTask = replace(fastTask, when: isPanelVisible || page) { await $0.runFastLane(includesTransfers: page) }
        processTask = replace(processTask, when: page) { await $0.runProcessLane() }
        statusTask = replace(statusTask, when: page) { await $0.runStatusLane() }
        capacityTask = replace(capacityTask, when: page) { await $0.runCapacityLane() }
        if page { startObserving() } else { stopObserving() }
    }

    /// Cancels `task` and, when `wanted`, starts `lane` once it has finished.
    private func replace(_ task: Task<Void, Never>?, when wanted: Bool,
                         lane: @escaping @MainActor (SystemMonitor) async -> Void) -> Task<Void, Never>? {
        task?.cancel()
        guard wanted else { return nil }
        return Task { [weak self] in
            await task?.value
            guard let self, !Task.isCancelled else { return }
            await lane(self)
        }
    }

    private func runFastLane(includesTransfers transfers: Bool) async {
        var delay = Self.firstFastDelay
        while !Task.isCancelled {
            // After a pause, load averaged over the time nobody looked is noise.
            let isAfterGap = Date.now.timeIntervalSince(lastSample) > Self.maxGap
            let transfersAfterGap = transfers && Date.now.timeIntervalSince(lastTransferSample) > Self.maxGap
            let rematch = transfers && drivesChanged
            if rematch { drivesChanged = false }
            let (reader, networkReader, diskReader) = (reader, networkReader, diskReader)
            let reading = await Task.detached(priority: .utility) {
                if isAfterGap { reader.resetCPUBaseline() }
                if transfersAfterGap {
                    networkReader.resetBaseline()
                    diskReader.resetBaseline()
                }
                if rematch { diskReader.invalidateDrives() }
                return FastReading(system: reader.read(),
                                   network: transfers ? networkReader.read() : nil,
                                   disk: transfers ? diskReader.read() : nil)
            }.value
            guard !Task.isCancelled else { return }
            publish(reading, includesTransfers: transfers)
            try? await Task.sleep(for: delay)
            delay = Self.interval
        }
    }

    private func runProcessLane() async {
        var delay = Self.firstProcessDelay
        while !Task.isCancelled {
            let isAfterGap = Date.now.timeIntervalSince(lastProcessSample) > Self.maxGap
            let (reader, limit) = (processReader, Self.processLimit)
            let ranking = await Task.detached(priority: .utility) {
                if isAfterGap { reader.resetBaseline() }
                return reader.read(limit: limit)
            }.value
            guard !Task.isCancelled else { return }
            lastProcessSample = .now
            if let ranking {
                // Right after a reset CPU has no figures yet; keep the last
                // ones rather than flashing the placeholder.
                let shown = ProcessRanking(byCPU: ranking.byCPU ?? processes?.byCPU, byMemory: ranking.byMemory)
                if shown != processes { processes = shown }
            } else if processes != nil {
                processes = nil
            }
            try? await Task.sleep(for: delay)
            delay = Self.processInterval
        }
    }

    private func runStatusLane() async {
        while !Task.isCancelled {
            let load = await Task.detached(priority: .utility) { SystemReader.loadAverage() }.value
            guard !Task.isCancelled else { return }
            if load != loadAverage { loadAverage = load }
            let minutes = hardware.bootDate.map { (Date.now.timeIntervalSince($0) / 60).rounded(.down) * 60 }
            if minutes != uptime { uptime = minutes }
            try? await Task.sleep(for: Self.statusInterval)
        }
    }

    private func runCapacityLane() async {
        while !Task.isCancelled {
            let (volumes, interface) = await Task.detached(priority: .utility) {
                (DiskReader.volumes(), NetworkReader.primaryInterface())
            }.value
            guard !Task.isCancelled else { return }
            let shown = volumes?.map(\.displayed)
            if shown != self.volumes { self.volumes = shown }
            let link = interface.map(NetworkLink.connected) ?? .disconnected
            if link != networkLink { networkLink = link }
            try? await Task.sleep(for: Self.capacityInterval)
        }
    }

    /// Reads capacity and the interface label now instead of at the next
    /// 30-second tick.
    private func refreshCapacity() {
        capacityTask = replace(capacityTask, when: isPageVisible) { await $0.runCapacityLane() }
    }

    // MARK: Events

    /// Thermal state and mounts are pushed by the system, so they're
    /// observed (only while the page is visible) rather than polled.
    private func startObserving() {
        guard observers.isEmpty else { return }
        thermalState = ProcessInfo.processInfo.thermalState
        // Posted on an arbitrary thread: hop to the main actor to read it.
        let thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.updateThermalState() }
        }
        observers.append((NotificationCenter.default, thermal))

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.volumesChanged() }
            }
            observers.append((workspace, token))
        }
    }

    private func stopObserving() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
    }

    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        if state != thermalState { thermalState = state }
    }

    private func volumesChanged() {
        drivesChanged = true
        refreshCapacity()
    }

    // MARK: Publishing

    private nonisolated struct FastReading: Sendable {
        var system: SystemSnapshot
        var network: NetworkReader.Reading?
        var disk: DiskReader.Reading?
    }

    private func publish(_ reading: FastReading, includesTransfers transfers: Bool) {
        let now = Date.now
        lastSample = now
        // The first reading after a reset has no CPU load yet; keep showing
        // the last one rather than flashing back to the placeholder.
        if let newCPU = reading.system.cpu, newCPU != cpu { cpu = newCPU }
        if reading.system.gpu != gpu { gpu = reading.system.gpu }
        if !MemoryUsage.displaysSame(reading.system.memory, memory) { memory = reading.system.memory }

        if transfers {
            lastTransferSample = now
            // Rates need two readings, so the first after a reset keeps the
            // last ones on screen, as CPU load does.
            let networkStatus = reading.network.map {
                TransferStatus(rates: $0.rates ?? network?.rates, totals: $0.totals, sourceCount: $0.interfaces.count)
            }
            if networkStatus != network { network = networkStatus }
            // A new or vanished interface may mean a new primary one.
            if let interfaces = reading.network?.interfaces, interfaces != lastInterfaces {
                if lastInterfaces != nil { refreshCapacity() }
                lastInterfaces = interfaces
            }
            let diskStatus = reading.disk.map {
                TransferStatus(rates: $0.rates ?? disk?.rates, totals: $0.totals, sourceCount: $0.driveCount)
            }
            if diskStatus != disk { disk = diskStatus }
        }

        // History is only drawn by the System page; the panel never reads
        // it, so nothing is recorded (or invalidated) for the panel alone.
        guard isPageVisible else { return }
        // A gap in the sparklines would join two unrelated moments with a
        // straight line, so history restarts after a pause.
        if now.timeIntervalSince(lastHistorySample) > Self.maxGap {
            for history in [\SystemMonitor.cpuHistory, \.gpuHistory, \.memoryHistory, \.downloadHistory,
                            \.uploadHistory, \.diskReadHistory, \.diskWriteHistory] where self[keyPath: history].count > 0 {
                self[keyPath: history].removeAll()
            }
        }
        lastHistorySample = now
        if let cpu = reading.system.cpu { cpuHistory.append(cpu.total) }
        if let gpu = reading.system.gpu { gpuHistory.append(gpu.utilization) }
        if let memory = reading.system.memory { memoryHistory.append(memory.fraction) }
        if let rates = reading.network?.rates {
            downloadHistory.append(rates.inbound)
            uploadHistory.append(rates.outbound)
        }
        if let rates = reading.disk?.rates {
            diskReadHistory.append(rates.inbound)
            diskWriteHistory.append(rates.outbound)
        }
    }
}

/// Whether the Mac has a network connection, from the interface carrying
/// the default route. Interfaces can be up with no link (an empty
/// Thunderbolt port), so their count alone can't tell.
nonisolated enum NetworkLink: Equatable, Sendable {
    /// Not read yet.
    case unknown
    case disconnected
    case connected(NetworkInterfaceInfo)
}

/// Rates and totals for network or disk, rounded to what's shown.
nonisolated struct TransferStatus: Equatable, Sendable {
    /// Nil until two readings exist.
    var rates: ByteRates?
    var totals: ByteCounters
    /// Interfaces or drives counted; zero when nothing is connected.
    var sourceCount: Int

    init(rates: ByteRates?, totals: ByteCounters, sourceCount: Int) {
        self.rates = rates?.displayed
        self.totals = totals.displayed
        self.sourceCount = sourceCount
    }
}
