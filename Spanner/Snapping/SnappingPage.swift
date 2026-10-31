import SpannerCore
import SwiftUI

/// Main-window page for window snapping.
struct SnappingPage: View {
    @Environment(SnapController.self) private var snapping

    var body: some View {
        @Bindable var settings = snapping.settings
        Page {
            PageHeader(title: "Window Snapping",
                       subtitle: "Move windows into halves, thirds, quarters or your own grid, with a shortcut or by dragging.",
                       symbol: AppSection.snapping.symbol, tint: FeatureTint.snapping) {
                Toggle("Enable window snapping", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }

            if settings.isEnabled {
                MissingPermissionsGroup(needed: [.accessibility],
                                        footer: "Spanner needs Accessibility to move other apps' windows.")
            }

            SettingsGroup(title: "Dragging",
                          footer: "Drag a window's title bar to a side, corner or the top of the screen. Hold ⇧ while dragging to snap into the display's grid; keep holding and move to span several cells.") {
                SettingsRow(title: "Snap when dragging to screen edges", symbol: "hand.draw.fill", tint: FeatureTint.snapping) {
                    Toggle("Snap when dragging to screen edges", isOn: $settings.dragSnapping)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if settings.dragSnapping && snapping.nativeEdgeTilingEnabled {
                    SettingsRow(title: "macOS tiling is also on",
                                subtitle: "Both will react to the same drag. Turn off \"Drag windows to screen edges to tile\" in Desktop & Dock.",
                                symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        Button("Open Desktop & Dock") { snapping.openDesktopAndDockSettings() }
                    }
                }
            }

            ShortcutsGroup(settings: settings, unavailable: snapping.unavailableShortcuts)

            DisplayRulesGroup(settings: settings)
        }
        .onAppear(perform: snapping.refreshNativeTiling)
    }
}

private struct ShortcutsGroup: View {
    @Bindable var settings: SnapSettings
    let unavailable: Set<SnapAction>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SettingsGroup(title: "Shortcuts",
                          footer: unavailable.isEmpty
                              ? "Click a shortcut to change it. Press Delete while recording to remove it."
                              : "Shortcuts marked with a warning are used by another app. Pick a different one, or quit that app.") {
                ForEach(SnapAction.allCases) { action in
                    SettingsRow(title: action.title, symbol: action.symbol, tint: FeatureTint.snapping) {
                        HStack(spacing: Spacing.s) {
                            if unavailable.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("Another app already uses this shortcut.")
                            }
                            ShortcutRecorder(shortcut: Binding(get: { settings.shortcut(for: action) },
                                                               set: { settings.setShortcut($0, for: action) }))
                        }
                    }
                }
            }
            Button("Restore Default Shortcuts") { settings.resetShortcuts() }
                .padding(.horizontal, Spacing.xs)
        }
    }
}

/// One group of rules per connected display.
private struct DisplayRulesGroup: View {
    @Bindable var settings: SnapSettings
    @State private var screens = NSScreen.screens

    var body: some View {
        ForEach(screens, id: \.persistentKey) { screen in
            let key = screen.persistentKey
            let rule = Binding(get: { settings.rule(for: key) }, set: { settings.setRule($0, for: key) })
            SettingsGroup(title: screen.localizedName) {
                SettingsRow(title: "Snap at this display's edges", symbol: "rectangle.dashed", tint: .blue) {
                    Toggle("Snap at this display's edges", isOn: rule.edgeSnapping)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Gap between windows", subtitle: "\(Int(rule.wrappedValue.gap)) pt",
                            symbol: "arrow.left.and.right.square", tint: .gray) {
                    Slider(value: rule.gap, in: DisplaySnapRule.gapRange, step: 2) { Text("Gap between windows") }
                        .labelsHidden()
                        .frame(width: 200)
                }
                SettingsRow(title: "Grid", subtitle: "Cells used when you hold ⇧ while dragging.",
                            symbol: "square.grid.3x3.fill", tint: .purple) {
                    HStack(spacing: Spacing.l) {
                        GridPreview(grid: rule.wrappedValue.grid)
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            Stepper("\(rule.wrappedValue.gridColumns) columns", value: rule.gridColumns,
                                    in: DisplaySnapRule.gridRange)
                            Stepper("\(rule.wrappedValue.gridRows) rows", value: rule.gridRows,
                                    in: DisplaySnapRule.gridRange)
                        }
                        .monospacedDigit()
                        .fixedSize()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

private struct GridPreview: View {
    let grid: SnapGrid

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<grid.rows, id: \.self) { _ in
                GridRow {
                    ForEach(0..<grid.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(FeatureTint.snapping.opacity(0.35))
                    }
                }
            }
        }
        .frame(width: 64, height: 40)
        .animation(.spanner, value: grid)
        .accessibilityLabel("\(grid.columns) by \(grid.rows) grid")
    }
}
