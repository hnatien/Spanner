import AppKit
import SpannerCore
import SwiftUI

/// Click, then press a key combination to set a global shortcut. Escape
/// cancels; Delete clears it when clearing is allowed.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    var allowsClearing = true

    @Environment(AppModel.self) private var model
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Group {
                if isRecording {
                    Text(rejected ? "Add ⌃, ⌥ or ⌘" : "Type shortcut…")
                        .foregroundStyle(rejected ? .orange : .secondary)
                } else if let shortcut {
                    Keycaps(keys: shortcut.keycaps)
                } else {
                    Text("Record Shortcut").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(minWidth: 120, minHeight: 22)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(.quaternary.opacity(isRecording ? 1 : 0.6), in: .rect(cornerRadius: CornerRadius.s, style: .continuous))
            .contentShape(.rect(cornerRadius: CornerRadius.s, style: .continuous))
        }
        // Drawn in SwiftUI rather than .bordered, which hosts an AppKit button
        // per recorder and makes long lists of shortcuts scroll poorly.
        .buttonStyle(.plain)
        .help(isRecording ? "Press a key combination. Escape cancels\(allowsClearing ? ", Delete clears" : "")." : "Click to change")
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        rejected = false
        model.hotkeys.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { model.hotkeys.isSuspended = false }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyShortcut.carbonModifiers(fromCocoa: event.modifierFlags.rawValue)
        let keyCode = UInt32(event.keyCode)
        if modifiers == 0 {
            if keyCode == 0x35 { // Escape
                stop()
                return
            }
            if allowsClearing, keyCode == 0x33 || keyCode == 0x75 { // Delete, Forward Delete
                shortcut = nil
                stop()
                return
            }
        }
        let candidate = KeyShortcut(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            rejected = true
            NSSound.beep()
            return
        }
        shortcut = candidate
        stop()
    }
}
