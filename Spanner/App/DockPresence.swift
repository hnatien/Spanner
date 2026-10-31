import AppKit
import SwiftUI

/// Spanner is a menu bar app (LSUIElement), but while one of its windows is
/// open it should behave like a normal app: Dock icon, ⌘-Tab entry, menu bar
/// menus. This counts open windows and switches the activation policy.
@MainActor
private enum DockPresence {
    static var openWindows = 0

    static func windowAppeared() {
        openWindows += 1
        if openWindows == 1 {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    static func windowDisappeared() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension View {
    func showsInDock() -> some View {
        onAppear(perform: DockPresence.windowAppeared)
            .onDisappear(perform: DockPresence.windowDisappeared)
    }
}
