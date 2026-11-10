import SpannerCore
import SwiftUI

/// Main-window page turning whole features on and off. A feature that is
/// off stops running and leaves the sidebar and the menu bar panel.
struct FeaturesPage: View {
    var body: some View {
        Page {
            PageHeader(title: AppSection.features.title,
                       subtitle: "Turn off what you don't use. It stops running and leaves the sidebar and the menu bar panel.",
                       symbol: AppSection.features.symbol, tint: FeatureTint.features)

            SettingsGroup(title: "Features",
                          footer: "Each feature keeps its settings while it's off.") {
                ForEach(Feature.allCases) { FeatureRow(feature: $0) }
            }
        }
    }
}

private struct FeatureRow: View {
    let feature: Feature
    @Environment(FeatureRegistry.self) private var features
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let section = AppSection(feature)
        let isOn = features.isEnabled(feature)
        SettingsRow(title: section.title, subtitle: subtitle, symbol: section.symbol,
                    tint: isOn ? section.tint : .gray) {
            Toggle("Use \(section.title)", isOn: Binding(get: { isOn }, set: setEnabled))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    /// Animated, so the feature's sidebar row slides in or out and the
    /// rows below it move to make room, instead of the list jumping.
    private func setEnabled(_ isEnabled: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spanner) {
            features.setEnabled(isEnabled, for: feature)
        }
    }

    private var subtitle: String {
        switch feature {
        case .battery: "Battery health, power flow, energy use and headphone battery."
        case .system: "Live processor, graphics, memory, network and disk activity."
        case .switcher: "Switch between windows with previews."
        case .snapping: "Snap windows with shortcuts or by dragging to a screen edge."
        case .mouse: "Scroll direction, smooth scrolling and extra mouse buttons."
        case .sound: "Audio devices, per-app volume and the mic mute shortcut."
        case .displays: "Brightness and volume of external monitors."
        case .keepAwake: "Keep the Mac awake for as long as you need."
        }
    }
}
