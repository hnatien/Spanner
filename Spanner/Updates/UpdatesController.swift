import Combine
import Foundation
import Observation
import Sparkle

/// Wraps Sparkle 2. The updater only starts when the build carries a feed URL
/// and an EdDSA public key (Info.plist `SUFeedURL` / `SUPublicEDKey`); until
/// then update UI explains that updates aren't set up instead of failing.
@Observable
final class UpdatesController {
    let isConfigured: Bool
    private(set) var canCheckForUpdates = false

    /// Mirrors Sparkle's setting as stored state so SwiftUI observes it.
    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellable: AnyCancellable?

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty
        controller = SPUStandardUpdaterController(startingUpdater: isConfigured,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
