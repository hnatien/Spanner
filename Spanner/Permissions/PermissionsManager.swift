import AppKit
import ApplicationServices
import Observation

/// A privacy permission a Spanner module can need.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    /// Why Spanner asks, phrased for the person granting it.
    var rationale: String {
        switch self {
        case .accessibility:
            "Lets the switcher see your windows, bring the one you pick to the front, and notice when you release the shortcut."
        case .screenRecording:
            "Lets the switcher show live previews and window titles. Spanner only captures small thumbnails and never records or uploads your screen."
        }
    }

    fileprivate var settingsURL: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

/// Tracks whether Spanner holds each permission and helps the person grant it.
///
/// macOS gives no change notification for these grants, so status is polled.
/// Two traps from Phase 0 shape the checks:
/// - `CGPreflightScreenCaptureAccess()` keeps answering false after a grant
///   made while the app runs, so Screen Recording is detected from whether
///   other apps' window titles are visible (a passive check with no prompt).
/// - `CGRequestScreenCaptureAccess()` returns immediately instead of waiting,
///   so the UI must keep polling after asking.
@Observable
final class PermissionsManager {
    private(set) var accessibilityGranted = false
    private(set) var screenRecordingGranted = false
    /// Permissions the person has already asked for this launch, so the UI
    /// can switch from "Grant" to manual help.
    private(set) var requested: Set<Permission> = []

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibilityGranted
        case .screenRecording: screenRecordingGranted
        }
    }

    var allGranted: Bool { Permission.allCases.allSatisfy(isGranted) }

    /// Shows the system prompt where one exists, then opens the matching
    /// System Settings pane so the switch is one click away.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // The value of kAXTrustedCheckOptionPrompt; the C global itself
            // isn't concurrency-safe to reference under Swift 6.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                openSettings(for: permission)
            }
        case .screenRecording:
            // Don't open Settings here: macOS adds Spanner to the Screen &
            // System Audio Recording list when the person answers its own
            // prompt, and opening Settings at the same moment hides it. The
            // prompt appears only once per app, so the row then offers
            // Open Settings and Show in Finder (to add Spanner with +).
            _ = CGRequestScreenCaptureAccess()
        }
        requested.insert(permission)
        refresh()
    }

    func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    /// Selects Spanner in Finder so it can be dragged into a privacy list or
    /// picked from the + button when macOS didn't add it automatically.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Re-reads both permissions. Cheap enough to call every second.
    func refresh() {
        let accessibility = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess() || Self.canSeeOtherWindowTitles()
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if screen != screenRecordingGranted { screenRecordingGranted = screen }
    }

    /// Polls in the background for the lifetime of the app. The interval is
    /// short while something is missing (so onboarding reacts at once) and
    /// long once everything is granted (to notice revocation).
    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                let interval: Duration = self.allGranted ? .seconds(5) : .seconds(1)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Window titles of other processes are only visible with Screen
    /// Recording, so finding one proves the grant without prompting.
    private static func canSeeOtherWindowTitles() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let owner = window[kCGWindowOwnerName as String] as? String, owner != "Window Server",
                  let name = window[kCGWindowName as String] as? String else { return false }
            return !name.isEmpty
        }
    }
}
