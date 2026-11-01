import AppKit
import SpannerCore
import SwiftUI

/// Borderless, non-activating panel that floats the switcher above every
/// app, Space and full-screen window without taking focus from the app the
/// person is switching away from.
final class SwitcherPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(_ view: some View, contentSize: CGSize, on screen: NSScreen) {
        resize(contentSize: contentSize, on: screen)
        contentView = FirstClickHostingView(rootView: AnyView(view))
        orderFrontRegardless()
    }

    /// Centres the panel on `screen`, sized for the overlay plus its shadow.
    func resize(contentSize: CGSize, on screen: NSScreen) {
        let margin = OverlayMetrics.shadowMargin
        let size = CGSize(width: contentSize.width + margin * 2, height: contentSize.height + margin * 2)
        let area = screen.visibleFrame
        setFrame(CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                        width: size.width, height: size.height), display: true)
    }

    func dismiss() {
        orderOut(nil)
        contentView = nil
    }
}

/// The panel never becomes key, so clicks must act on the first click.
private final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SwitcherOverlayView: View {
    let session: SwitcherSession
    let onChoose: (CGWindowID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var metrics: OverlayMetrics { session.metrics }

    var body: some View {
        Group {
            if session.windows.isEmpty {
                EmptyStateView(symbol: "macwindow", title: "No windows",
                               message: emptyMessage)
                    .frame(maxHeight: .infinity)
            } else {
                grid
            }
        }
        .padding(OverlayMetrics.outerPadding)
        .glassSurface(cornerRadius: OverlayMetrics.cornerRadius)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        .padding(OverlayMetrics.shadowMargin)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { appeared = true }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: OverlayMetrics.gridSpacing),
                                         count: session.columns),
                          spacing: OverlayMetrics.gridSpacing) {
                    ForEach(Array(session.windows.enumerated()), id: \.element.id) { index, window in
                        SwitcherTile(window: window,
                                     thumbnail: session.thumbnails[window.id],
                                     icon: session.icon(for: window.pid),
                                     metrics: metrics,
                                     isSelected: index == session.selection.index,
                                     isHovered: session.hoveredID == window.id)
                            .id(window.id)
                            .onTapGesture { onChoose(window.id) }
                            .onHover { inside in
                                if inside { session.hoveredID = window.id } else if session.hoveredID == window.id { session.hoveredID = nil }
                            }
                            .accessibilityAction { onChoose(window.id) }
                    }
                }
                .animation(reduceMotion ? nil : .spanner, value: session.selection.index)
            }
            .scrollIndicators(.never)
            .onChange(of: session.selection.index) {
                if let id = session.selectedWindow?.id {
                    withAnimation(reduceMotion ? nil : .spanner) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var emptyMessage: String {
        switch session.mode {
        case .allWindows: "Open a window in any app and it will show up here."
        case .currentApp(let name): "\(name.isEmpty ? "This app" : name) has no windows to switch to."
        }
    }
}

private struct SwitcherTile: View {
    let window: SwitcherWindow
    let thumbnail: NSImage?
    let icon: NSImage
    let metrics: OverlayMetrics
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        VStack(spacing: OverlayMetrics.titleSpacing) {
            preview
                .frame(width: metrics.tileWidth, height: metrics.thumbnailHeight)
                .overlay(alignment: .bottomLeading) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .offset(x: -4, y: 6)
                }
                .overlay(alignment: .topTrailing) { badge }

            Text(window.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: metrics.tileWidth, height: OverlayMetrics.titleHeight)
                // An animated weight builds a new variable-font instance and
                // re-rasterizes every glyph each frame; switch it instantly.
                .transaction { $0.animation = nil }
        }
        .padding(OverlayMetrics.cellPadding)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.l + 2, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.07 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.l + 2, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        }
        .contentShape(.rect(cornerRadius: CornerRadius.l + 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: CornerRadius.m, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: CornerRadius.m, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let text = badgeText {
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: .capsule)
                .padding(6)
        }
    }

    private var badgeText: String? {
        if window.isMinimized { return "Minimized" }
        if window.isElsewhere { return "Other Space" }
        return nil
    }

    private var accessibilityText: String {
        var parts = [window.title]
        if window.title != window.appName { parts.append(window.appName) }
        if let badgeText { parts.append(badgeText) }
        return parts.joined(separator: ", ")
    }
}
