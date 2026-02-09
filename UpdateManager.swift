import Foundation
import Sparkle

/// Manages automatic updates via Sparkle framework
class UpdateManager: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        // Initialize Sparkle with standard user interface
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe when updates can be checked
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Listen for launch-time update check
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CheckForUpdatesOnLaunch"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    /// Manually check for updates
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Access the updater for menu integration
    var updater: SPUUpdater {
        updaterController.updater
    }
}
