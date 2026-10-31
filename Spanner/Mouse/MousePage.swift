import SpannerCore
import SwiftUI

/// Main-window page for mouse fixes.
struct MousePage: View {
    @Environment(MouseController.self) private var mouse

    var body: some View {
        @Bindable var settings = mouse.settings
        Page {
            PageHeader(title: "Mouse",
                       subtitle: "Give a wheel mouse its own scroll direction, smooth out notchy scrolling, and put extra buttons to work.",
                       symbol: AppSection.mouse.symbol, tint: FeatureTint.mouse) {
                Toggle("Enable mouse fixes", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }

            if settings.isEnabled {
                MissingPermissionsGroup(needed: [.accessibility],
                                        footer: "Spanner needs Accessibility to adjust scroll and button events.")
                if mouse.status == .tapFailed {
                    Label("macOS didn't let Spanner watch the mouse. Remove Spanner from Accessibility, add it again, then turn this off and on.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            SettingsGroup(title: "Scrolling",
                          footer: "Applies to wheel mice only. Trackpads and Magic Mouse keep the direction set in System Settings.") {
                SettingsRow(title: "Wheel direction",
                            subtitle: "Natural moves content with your finger, like a trackpad. Standard moves the scroll bar.",
                            symbol: "arrow.up.arrow.down", tint: FeatureTint.mouse) {
                    Picker("Wheel direction", selection: $settings.scrollDirection) {
                        ForEach(MouseScrollDirection.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Smooth scrolling",
                            subtitle: "Turns each wheel click into a short glide. Quick flicks go further.",
                            symbol: "water.waves", tint: .teal) {
                    Toggle("Smooth scrolling", isOn: $settings.smoothScrolling)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if settings.smoothScrolling {
                    SettingsRow(title: "Distance per click", symbol: "ruler", tint: .gray) {
                        Slider(value: $settings.scrollSpeed, in: MouseSettings.speedRange) {
                            Text("Distance per click")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    SettingsRow(title: "Glide", symbol: "wind", tint: .gray) {
                        Slider(value: $settings.glide, in: MouseSettings.glideRange) {
                            Text("Glide")
                        } minimumValueLabel: {
                            Text("Short").font(.caption)
                        } maximumValueLabel: {
                            Text("Long").font(.caption)
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }
            }

            SettingsGroup(title: "Buttons",
                          footer: "Mission Control and App windows press their default shortcuts (⌃↑ and ⌃↓), so they follow your Keyboard settings.") {
                ForEach(MouseButton.allCases) { button in
                    SettingsRow(title: button.title, symbol: symbol(for: button), tint: .indigo) {
                        Picker(button.title, selection: Binding(get: { settings.action(for: button) },
                                                                set: { settings.buttonActions[button] = $0 })) {
                            ForEach(button.choices) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func symbol(for button: MouseButton) -> String {
        switch button {
        case .middle: "computermouse.fill"
        case .back: "chevron.backward.circle.fill"
        case .forward: "chevron.forward.circle.fill"
        }
    }
}
