import SwiftUI

@main
struct SpannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .injectServices(appDelegate.model)
        } label: {
            MenuBarIcon()
                .injectServices(appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Spanner", id: WindowID.main) {
            MainWindow()
                .injectServices(appDelegate.model)
                .showsInDock()
        }
        .defaultSize(width: 940, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand(model: appDelegate.model)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updates: appDelegate.model.updates)
            }
        }

        Window("Welcome to Spanner", id: WindowID.onboarding) {
            OnboardingView()
                .injectServices(appDelegate.model)
                .showsInDock()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// ⌘, opens the main window on General, since Spanner has no separate
/// Settings scene.
private struct SettingsCommand: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            model.selectedSection = .general
            openWindow(id: WindowID.main)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

private struct CheckForUpdatesCommand: View {
    let updates: UpdatesController

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.isConfigured || !updates.canCheckForUpdates)
    }
}
