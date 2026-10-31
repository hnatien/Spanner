import SwiftUI

// Reusable building blocks. Pages compose these instead of styling raw stacks,
// so typography, padding and surfaces stay consistent across modules.

/// A rounded, colour-filled square holding an SF Symbol, like the icons in
/// System Settings' sidebar.
struct SymbolTile: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Title block at the top of every main-window page.
struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            SymbolTile(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.l)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String, symbol: String, tint: Color) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// Scrollable page container used by every main-window section.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                content
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Content surface for dashboard data. Uses an opaque secondary background:
/// Liquid Glass is reserved for floating controls, not content.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: CornerRadius.l, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.l, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

/// A titled group of settings rows separated by hairlines, matching the
/// grouped-form look of System Settings while allowing custom rows.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, Spacing.xs)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.l)
                        }
                        subview
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.m)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: CornerRadius.l, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.l, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row inside a SettingsGroup: label and optional explanation on the
/// left, a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = .accentColor
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            if let symbol {
                SymbolTile(symbol: symbol, tint: tint, size: 24)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.l)
            control
        }
        .frame(minHeight: 24)
    }
}

/// A labelled metric: small caption, large monospaced value, optional detail.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label {
                Text(title)
            } icon: {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A compact capsule describing a state ("Charging", "Granted").
struct StatusPill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal fill gauge for a 0...1 fraction.
struct MeterBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.spanner, value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// Keyboard shortcut rendered as keycaps, e.g. ⌥ ⇥.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, Spacing.xs)
                    .background(.background, in: .rect(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(keys.joined(separator: " ")))
    }
}

/// Empty or unavailable state with an icon, message and optional action.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            actions
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a translucent material before that. For
    /// floating surfaces only (switcher overlay, popovers), never content.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular,
                        in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Prominent button style: glass on macOS 26+, bordered prominent before.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
