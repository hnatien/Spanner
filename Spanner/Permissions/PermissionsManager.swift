import AppKit
import ApplicationServices
import CoreBluetooth
import Observation

/// A privacy permission a Spanner module can need.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case systemAudio
    case bluetooth

    var id: Self { self }

    /// Permissions the headline features need, which the menu bar nags
    /// about. Others are asked for only when their module is turned on.
    static let core: [Permission] = [.accessibility, .screenRecording]

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .systemAudio: "System Audio Recording"
        case .bluetooth: "Bluetooth"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .systemAudio: "waveform"
        case .bluetooth: "headphones"
        }
    }

    /// Why Spanner asks, phrased for the person granting it.
    var rationale: String {
        switch self {
        case .accessibility:
            "Lets the switcher see and raise your windows, window snapping move them, mouse fixes adjust scrolling and buttons, and media keys reach external displays."
        case .screenRecording:
            "Lets the switcher show live previews and window titles. Spanner only captures small thumbnails and never records or uploads your screen."
        case .systemAudio:
            "Lets the volume mixer turn individual apps up or down. Audio passes straight to your speakers; Spanner never records or saves it."
        case .bluetooth:
            "Lets Spanner read your AirPods' and headphones' battery and notice when you put them on."
        }
    }

    fileprivate var settingsURL: URL {
        // System audio is listed in the same pane, under "System Audio
        // Recording Only".
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording, .systemAudio: "Privacy_ScreenCapture"
        case .bluetooth: "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

/// System audio capture has no public status API. The TCC SPI below is what
/// Apple's own tools and AudioCap use; Phase 2 confirmed both symbols exist
/// on macOS 27.2. Results: 0 granted, 1 denied, 2 not asked yet.
private enum AudioCaptureAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString
    private nonisolated(unsafe) static let library = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    /// Nil when the SPI is unavailable; macOS then prompts on first use.
    static var isGranted: Bool? {
        guard let symbol = dlsym(library, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)(service, nil) == 0
    }

    /// Shows the system prompt. Returns false if the SPI is unavailable.
    static func request(completion: @escaping @Sendable (Bool) -> Void) -> Bool {
        guard let symbol = dlsym(library, "TCCAccessRequest") else { return false }
        unsafeBitCast(symbol, to: Request.self)(service, nil, completion)
        return true
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
    private(set) var systemAudioGranted = false
    private(set) var bluetoothGranted = false
    /// Permissions the person has already asked for this launch, so the UI
    /// can switch from "Grant" to manual help.
    private(set) var requested: Set<Permission> = []

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Creating a central manager is what shows the Bluetooth prompt; it's
    /// kept so the prompt stays up until answered.
    @ObservationIgnored private var bluetoothPrompt: CBCentralManager?

    init() {
        refresh()
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibilityGranted
        case .screenRecording: screenRecordingGranted
        case .systemAudio: systemAudioGranted
        case .bluetooth: bluetoothGranted
        }
    }

    /// Whether the headline features have what they need.
    var allGranted: Bool { Permission.core.allSatisfy(isGranted) }

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
        case .systemAudio:
            let prompted = AudioCaptureAccess.request { _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            if !prompted { openSettings(for: permission) }
        case .bluetooth:
            // macOS prompts only while undecided; after a denial the switch
            // is in Settings.
            if CBManager.authorization == .notDetermined {
                bluetoothPrompt = CBCentralManager(delegate: nil, queue: nil)
            } else {
                openSettings(for: permission)
            }
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

    /// Re-reads every permission. Cheap enough to call every second.
    func refresh() {
        let accessibility = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess() || Self.canSeeOtherWindowTitles()
        // Without the SPI, assume granted and let macOS prompt on first use.
        let audio = AudioCaptureAccess.isGranted ?? true
        let bluetooth = CBManager.authorization == .allowedAlways
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if screen != screenRecordingGranted { screenRecordingGranted = screen }
        if audio != systemAudioGranted { systemAudioGranted = audio }
        if bluetooth != bluetoothGranted { bluetoothGranted = bluetooth }
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
