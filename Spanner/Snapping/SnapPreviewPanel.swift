import AppKit
import SwiftUI

/// Translucent outline showing where a dragged window will land.
final class SnapPreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        contentView = NSHostingView(rootView: SnapPreviewView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the preview over an Accessibility-space rect.
    func show(axFrame: CGRect) {
        let target = NSScreen.appKitRect(fromAX: axFrame)
        if isVisible {
            guard frame != target else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
            orderFrontRegardless()
        }
    }

    func hide() {
        orderOut(nil)
    }
}

private struct SnapPreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.l, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.l, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
            }
            .padding(2)
    }
}
