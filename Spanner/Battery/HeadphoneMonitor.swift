import Foundation
import IOBluetooth
import Observation
import SpannerCore

/// Tracks connected headphones' battery and shows it on screen when the
/// person starts using them (puts AirPods in, or connects headphones without
/// ear detection). Off by default because it needs the Bluetooth permission.
///
/// IOBluetooth has no notification for battery or ear changes, so they're
/// polled: often while headphones are connected, rarely otherwise. A connect
/// notification cuts the wait when headphones first come in.
@Observable
final class HeadphoneMonitor {
    private(set) var headphones: [HeadphoneBattery] = []

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }

    @ObservationIgnored private let permissions: PermissionsManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let hud = HUDPanel()
    @ObservationIgnored private var detector = HeadphoneUsageDetector()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var connectObserver: ConnectObserver?
    /// Polls fast until then after a connection, while battery reports come in.
    @ObservationIgnored private var connectedRecently = Date.distantPast

    private static let enabledKey = "battery.headphonesEnabled"
    private static let connectedInterval: Duration = .seconds(3)
    private static let idleInterval: Duration = .seconds(20)
    private static let connectGrace: TimeInterval = 30

    init(permissions: PermissionsManager, defaults: UserDefaults = .standard) {
        self.permissions = permissions
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func start() {
        guard isEnabled, pollTask == nil else { return }
        schedulePolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        connectObserver?.invalidate()
        connectObserver = nil
        detector = HeadphoneUsageDetector()
        headphones = []
    }

    private func refresh() {
        // IOBluetooth calls before the grant would make macOS prompt from a
        // background poll; the battery page asks instead.
        guard permissions.isGranted(.bluetooth) else { return }
        if connectObserver == nil {
            connectObserver = ConnectObserver { [weak self] in
                guard let self else { return }
                self.connectedRecently = .now
                self.schedulePolling()
            }
        }
        let current = HeadphoneReader.connected()
        if current != headphones { headphones = current }
        if let started = detector.update(current, now: .now).first {
            showHUD(for: started)
        }
    }

    private func schedulePolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    private var pollInterval: Duration {
        let fast = !headphones.isEmpty || Date.now.timeIntervalSince(connectedRecently) < Self.connectGrace
        return fast ? Self.connectedInterval : Self.idleInterval
    }

    private func showHUD(for headphone: HeadphoneBattery) {
        hud.show(symbol: headphone.symbol, title: headphone.name,
                 level: headphone.lowest.map { Double($0) / 100 },
                 subtitle: headphone.summary, duration: .seconds(4))
    }
}

extension HeadphoneBattery {
    var symbol: String {
        switch kind {
        case .airPods: "airpods"
        case .airPodsPro: "airpods.pro"
        case .airPodsMax: "airpods.max"
        case .other: "headphones"
        }
    }
}

/// Bridges IOBluetooth's target/selector connect notification to a closure.
private final class ConnectObserver: NSObject {
    private let onConnect: @MainActor @Sendable () -> Void
    private var registration: IOBluetoothUserNotification?

    init(onConnect: @escaping @MainActor @Sendable () -> Void) {
        self.onConnect = onConnect
        super.init()
        registration = IOBluetoothDevice.register(forConnectNotifications: self,
                                                  selector: #selector(deviceConnected(_:device:)))
    }

    func invalidate() {
        registration?.unregister()
        registration = nil
    }

    /// On macOS 27 IOBluetooth delivers this on its own queue, not the main
    /// thread, so it must be nonisolated: a main-actor method called there
    /// fails Swift's isolation check and crashes. Battery levels usually
    /// arrive a moment after the link comes up, so the fast polls that follow
    /// pick them up.
    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification,
                                                   device: IOBluetoothDevice) {
        let onConnect = onConnect
        Task { @MainActor in onConnect() }
    }
}
