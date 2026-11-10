import SpannerCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(PermissionsManager.self) private var permissions
    @Environment(FeatureRegistry.self) private var features

    private static let appSections: [AppSection] = [.features, .menuBar, .permissions, .general]

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                // Features that are turned off have no page.
                if !features.enabledFeatures.isEmpty {
                    Section("Features") {
                        ForEach(features.enabledFeatures.map(AppSection.init)) { sidebarRow($0) }
                    }
                }
                Section("Spanner") {
                    ForEach(Self.appSections) { sidebarRow($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(for: model.selectedSection)
                .frame(minWidth: 560, minHeight: 520)
        }
        .navigationTitle(model.selectedSection.title)
    }

    private var selection: Binding<AppSection?> {
        Binding(get: { model.selectedSection },
                set: { if let section = $0 { model.selectedSection = section } })
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            SymbolTile(symbol: section.symbol, tint: section.tint, size: 22)
        }
        .badge(section == .permissions && !permissions.allGranted ? Text("!") : nil)
        .tag(section)
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .battery: BatteryDashboardPage()
        case .system: SystemPage()
        case .switcher: SwitcherSettingsPage()
        case .snapping: SnappingPage()
        case .mouse: MousePage()
        case .sound: SoundPage()
        case .displays: DisplaysPage()
        case .keepAwake: KeepAwakePage()
        case .features: FeaturesPage()
        case .menuBar: MenuBarSettingsPage()
        case .permissions: PermissionsPage()
        case .general: GeneralPage()
        }
    }
}
