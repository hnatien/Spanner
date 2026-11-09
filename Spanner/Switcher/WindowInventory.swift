import AppKit
import ApplicationServices
import SpannerCore

/// One window as the switcher shows it.
struct SwitcherWindow: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    /// Window title, or the app name when the window has none.
    let title: String
    let appName: String
    let isMinimized: Bool
    /// On another Space or in a hidden app.
    let isElsewhere: Bool
    let size: CGSize
}

/// Accessibility facts about one window. AXUIElement is a thread-safe CF
/// object, so it can cross from the background reader to the main actor.
nonisolated struct AXWindowInfo: @unchecked Sendable {
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
}

/// Knows which windows exist and how recently each app was used, and can
/// bring a window to the front.
///
/// The window list comes from CGWindowList, which is synchronous and fast,
/// so opening the switcher never waits. Accessibility data (titles,
/// minimized state, the element needed to raise a window) is slower and can
/// hang on unresponsive apps, so it is read in the background into a cache
/// and merged when it arrives.
final class WindowInventory {
    private var axCache: [pid_t: [CGWindowID: AXWindowInfo]] = [:]
    private(set) var appRecency: [pid_t] = []
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var desktopMemory = DesktopMemory()

    /// Called on the main actor after a background Accessibility read lands.
    var onAccessibilityRefresh: (() -> Void)?

    func startTracking() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.noteActivated(pid)
                self?.refreshAccessibility(pids: [pid])
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.axCache[pid] = nil
                self?.appRecency.removeAll { $0 == pid }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopMemory.note(Self.displaySpaces()) }
        })
        desktopMemory.note(Self.displaySpaces())
        if let front = NSWorkspace.shared.frontmostApplication {
            noteActivated(front.processIdentifier)
        }
    }

    func stopTracking() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        refreshTask?.cancel()
    }

    private func noteActivated(_ pid: pid_t) {
        appRecency.removeAll { $0 == pid }
        appRecency.insert(pid, at: 0)
    }

    /// Re-reads Accessibility windows in the background; all regular apps
    /// when `pids` is nil.
    func refreshAccessibility(pids: [pid_t]? = nil) {
        guard AXIsProcessTrusted() else { return }
        // Spanner's own windows are read from AppKit instead; Accessibility
        // calls into our own process would wait on the main thread.
        let targets = (pids ?? Self.regularApps().map(\.processIdentifier)).filter { $0 != Self.ownPID }
        let previous = refreshTask
        refreshTask = Task { [weak self] in
            await previous?.value
            let result = await Task.detached(priority: .userInitiated) {
                var windows: [pid_t: [CGWindowID: AXWindowInfo]] = [:]
                for pid in targets { windows[pid] = AXReader.windows(of: pid) }
                return windows
            }.value
            guard let self, !Task.isCancelled else { return }
            self.axCache.merge(result) { _, new in new }
            self.onAccessibilityRefresh?()
        }
    }

    /// Current window list for the switcher, already filtered and ordered.
    func windows(options: WindowListOptions) -> [SwitcherWindow] {
        let apps = Dictionary(Self.regularApps().map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let all = Self.windowInfo([.optionAll, .excludeDesktopElements])
        let zOrder = Self.windowInfo([.optionOnScreenOnly, .excludeDesktopElements])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }

        let displays = Self.displaySpaces()
        desktopMemory.note(displays)
        let visibleSpaces = Set(displays.map(\.current))
        let coveredDesktops = desktopMemory.coveredDesktops(displays)
        var sizes: [CGWindowID: CGSize] = [:]
        let candidates: [WindowCandidate] = all.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = apps[pid] else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            let ax = axCache[pid]?[id]
            let ownWindow = pid == Self.ownPID ? NSApp.window(withWindowNumber: Int(id)) : nil
            let serverName = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let placement = isOnScreen || app.isHidden ? (isOrderedOut: false, isBehindFullScreen: false)
                : WindowPlacement.classify(isOrderedIn: Self.isOrderedIn(id), spaces: { Self.spaces(of: id) },
                                           visibleSpaces: visibleSpaces, coveredDesktops: coveredDesktops)
            sizes[id] = bounds.size
            return WindowCandidate(id: id, pid: pid, appName: app.localizedName ?? "",
                                   title: ownWindow?.title
                                       ?? ax.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? serverName,
                                   width: bounds.width, height: bounds.height,
                                   layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                   isOnScreen: isOnScreen,
                                   hasAXElement: ax != nil || ownWindow != nil,
                                   isMinimized: ownWindow?.isMiniaturized ?? ax?.isMinimized ?? false,
                                   isOrderedOut: placement.isOrderedOut,
                                   isBehindFullScreen: placement.isBehindFullScreen)
        }

        return WindowListBuilder.build(candidates, zOrder: zOrder, appRecency: appRecency, options: options).map {
            SwitcherWindow(id: $0.id, pid: $0.pid, title: $0.title.isEmpty ? $0.appName : $0.title,
                           appName: $0.appName, isMinimized: $0.isMinimized, isElsewhere: $0.isElsewhere,
                           size: sizes[$0.id] ?? .zero)
        }
    }

    /// Brings a window forward: unhide its app, unminimize, raise it, then
    /// make its app frontmost with only that window brought forward, so the
    /// app's other windows keep their place below the previous window and
    /// the next switch returns to it. Works from a background app, where
    /// `NSRunningApplication.activate()` may be refused under macOS 14+
    /// cooperative activation.
    ///
    /// Falls back to activating the whole app if the window server call
    /// fails. Windows on another Space have no Accessibility element; the
    /// window server call still moves to the window's Space.
    func focus(_ window: SwitcherWindow) {
        if window.pid == Self.ownPID {
            focusOwn(window.id)
            return
        }
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true { app?.unhide() }
        let element = axCache[window.pid]?[window.id]?.element
        if let element {
            if window.isMinimized {
                AXUIElementSetAttributeValue(element, AXAttribute.minimized, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(element, AXAttribute.main, kCFBooleanTrue)
            AXUIElementPerformAction(element, AXAttribute.raise)
        }
        if !Self.makeFrontmost(pid: window.pid, windowID: window.id) {
            let appElement = AXUIElementCreateApplication(window.pid)
            AXUIElementSetAttributeValue(appElement, AXAttribute.frontmost, kCFBooleanTrue)
            app?.activate()
        }
        if let element {
            // The app may re-order its own windows as it activates; raise
            // again once activation has landed.
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                AXUIElementPerformAction(element, AXAttribute.raise)
            }
        }
    }

    /// Makes `pid` the front process with only `windowID` brought forward,
    /// then makes that window key, as AltTab does. False if the window
    /// server refused or the calls are missing.
    private static func makeFrontmost(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess = SkyLight.setFrontProcess, let postEventRecord = SkyLight.postEventRecord else {
            return false
        }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr,
              setFrontProcess(&psn, windowID, SkyLight.userGenerated) == .success else { return false }
        // Key-window event record: 0xf8 bytes, window ID at 0x3c, sent once
        // as "focus out" (0x01) and once as "focus in" (0x02).
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        bytes.replaceSubrange(0x20..<0x30, with: repeatElement(0xff, count: 0x10))
        for phase: UInt8 in [0x01, 0x02] {
            bytes[0x08] = phase
            _ = postEventRecord(&psn, &bytes)
        }
        return true
    }

    /// Spanner's own windows are raised through AppKit directly.
    private func focusOwn(_ id: CGWindowID) {
        guard let window = NSApp.window(withWindowNumber: Int(id)) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The app's icon as a fixed bitmap. App icons are IconServices images
    /// that SwiftUI re-renders on every frame, which made cycling the
    /// switcher with a held Tab cost a large share of a CPU core.
    func icon(for pid: pid_t) -> NSImage {
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
        return Self.rasterized(icon)
    }

    /// Draws `icon` once at 128 px, enough for the 56 pt tile icon on Retina.
    private static func rasterized(_ icon: NSImage) -> NSImage {
        let pixels = 128
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return icon
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return icon }
        return NSImage(cgImage: image, size: NSSize(width: pixels / 2, height: pixels / 2))
    }

    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Apps that can own switchable windows. Spanner itself is included only
    /// while one of its windows is open, since that is when DockPresence
    /// makes it a regular app; its overlay and menu bar panel sit above
    /// layer 0 and are filtered out by WindowListBuilder.
    private static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    /// The window server's ordered-in flag, nil if the call fails.
    private static func isOrderedIn(_ id: CGWindowID) -> Bool? {
        var orderedIn = DarwinBoolean(false)
        guard CGSWindowIsOrderedIn(CGSMainConnectionID(), id, &orderedIn) == .success else { return nil }
        return orderedIn.boolValue
    }

    /// The window's Spaces, nil if the lookup fails.
    private static func spaces(of id: CGWindowID) -> [Int]? {
        CGSCopySpacesForWindows(CGSMainConnectionID(), 7, [id] as CFArray)?.takeRetainedValue() as? [Int]
    }

    /// Each display's current Space and desktops. Full-screen Spaces have
    /// type 4; ordinary desktops type 0.
    private static func displaySpaces() -> [DisplaySpaces] {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] ?? []
        return displays.compactMap { display in
            guard let id = display["Display Identifier"] as? String,
                  let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int else { return nil }
            let desktops = (display["Spaces"] as? [[String: Any]] ?? [])
                .filter { $0["type"] as? Int == 0 }
                .compactMap { $0["ManagedSpaceID"] as? Int }
            return DisplaySpaces(display: id, current: current, desktops: desktops)
        }
    }

    private static func windowInfo(_ options: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }
}

/// Accessibility attribute and action names. String literals rather than the
/// kAX* globals, which Swift 6 flags as not concurrency-safe.
private enum AXAttribute {
    static let minimized = "AXMinimized" as CFString
    static let main = "AXMain" as CFString
    static let frontmost = "AXFrontmost" as CFString
    static let raise = "AXRaise" as CFString
}

/// Reads an app's windows through Accessibility. Runs off the main thread.
private enum AXReader {
    nonisolated static func windows(of pid: pid_t) -> [CGWindowID: AXWindowInfo] {
        let app = AXUIElementCreateApplication(pid)
        // Unresponsive apps would otherwise block for the 6 s default.
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [:] }
        var result: [CGWindowID: AXWindowInfo] = [:]
        for element in elements {
            var id: CGWindowID = 0
            guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { continue }
            result[id] = AXWindowInfo(element: element,
                                      title: string(element, "AXTitle") ?? "",
                                      isMinimized: bool(element, "AXMinimized") ?? false)
        }
        return result
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
