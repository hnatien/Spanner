import AppKit
import Observation
import SwiftUI

/// On-screen display for actions taken from the keyboard (external display
/// brightness and volume, mic mute) and for headphone battery. Appears below the menu bar at the top
/// right of the screen with the pointer, like the system HUD on macOS 26,
/// and fades after a moment.
final class HUDPanel: NSPanel {
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 260, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        contentView = NSHostingView(rootView: HUDView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows or updates the HUD. `level` (0...1) adds a meter; `screen`
    /// defaults to the one with the pointer.
    func show(symbol: String, title: String, level: Double?, subtitle: String? = nil,
              duration: Duration = .seconds(1.4), on screen: NSScreen? = nil) {
        model.symbol = symbol
        model.title = title
        model.subtitle = subtitle
        model.level = level
        let mouse = NSEvent.mouseLocation
        let target = screen ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let target {
            let area = target.visibleFrame
            let size = frame.size
            setFrameOrigin(CGPoint(x: area.maxX - size.width - Spacing.m, y: area.maxY - size.height - Spacing.m))
        }
        alphaValue = 1
        orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            self.orderOut(nil)
        }
    }
}

@Observable
private final class HUDModel {
    var symbol = "speaker.wave.2.fill"
    var title = ""
    var subtitle: String?
    var level: Double?
}

private struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: model.symbol)
                .font(.title2)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let level = model.level {
                    MeterBar(fraction: level, tint: .primary, height: 5)
                }
            }
        }
        .padding(.horizontal, Spacing.l)
        .frame(width: 260, height: 64)
        .glassSurface(cornerRadius: CornerRadius.xl)
        .accessibilityElement(children: .combine)
    }
}
