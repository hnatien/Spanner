import Foundation
import IOKit.pwr_mgt
import Observation
import OSLog
import SpannerCore

/// Keeps the Mac (and optionally the display) awake with an IOKit power
/// assertion, the same mechanism `caffeinate` uses. No permission needed.
@Observable
final class KeepAwakeController: FeatureModule {
    private(set) var session: KeepAwakeSession?
    private(set) var lastError: String?

    /// Whether new sessions also keep the display on. Remembered across launches.
    var keepsDisplayOn: Bool {
        didSet { UserDefaults.standard.set(keepsDisplayOn, forKey: Self.displayKey) }
    }

    /// Duration used by the one-click toggle in the menu bar.
    var defaultDuration: KeepAwakeDuration = .indefinitely

    var isActive: Bool { session != nil }

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    private static let displayKey = "keepAwake.keepsDisplayOn"
    private static let log = Logger(subsystem: "dev.spanner.Spanner", category: "KeepAwake")

    init() {
        keepsDisplayOn = UserDefaults.standard.object(forKey: Self.displayKey) as? Bool ?? true
    }

    func toggle() {
        isActive ? stop() : start(defaultDuration)
    }

    func start(_ duration: KeepAwakeDuration) {
        stop()
        let type = keepsDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Spanner Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else {
            lastError = "macOS refused the request (error \(String(result, radix: 16)))."
            Self.log.error("IOPMAssertionCreateWithName failed: \(result)")
            return
        }
        lastError = nil
        assertionID = id
        let session = KeepAwakeSession(duration: duration, keepsDisplayOn: keepsDisplayOn, now: .now)
        self.session = session
        if let end = session.end {
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        session = nil
    }
}
