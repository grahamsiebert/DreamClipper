import Foundation
import Sparkle

/// Manages automatic updates via Sparkle framework
class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!

    @Published var canCheckForUpdates = false
    @Published var updateAvailable = false
    @Published var updateVersion: String?

    override init() {
        super.init()

        // Initialize Sparkle with ourselves as delegate to receive update notifications
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Observe when updates can be checked
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Check for updates silently on launch (after a brief delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkForUpdatesInBackground()
        }
    }

    /// Silently check for updates in background (no UI)
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Manually check for updates (shows UI)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Access the updater for menu integration
    var updater: SPUUpdater {
        updaterController.updater
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.updateAvailable = true
            self.updateVersion = item.displayVersionString
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        DispatchQueue.main.async {
            self.updateAvailable = false
            self.updateVersion = nil
        }
    }
}
