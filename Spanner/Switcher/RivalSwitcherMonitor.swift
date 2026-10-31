import AppKit
import Observation
import SpannerCore

/// Watches for other window switchers (AltTab, Witch…) so the settings page
/// can explain why a shortcut opens someone else's switcher.
@Observable
final class RivalSwitcherMonitor {
    private(set) var runningNames: [String] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// Asks every running instance of the named switcher to quit normally,
    /// so it can save its state and restore anything it changed.
    func quit(_ name: String) {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, RivalSwitchers.known[id] == name {
                app.terminate()
            }
        }
    }

    private func refresh() {
        let names = RivalSwitchers.running(in: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if names != runningNames { runningNames = names }
    }
}
