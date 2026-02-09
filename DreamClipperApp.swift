import SwiftUI
import Sparkle

@main
struct DreamClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .frame(width: 1000, height: 700)
                .onDisappear {
                    // Clean up overlays when main window closes
                    viewModel.cleanupOverlays()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updateManager: updateManager)
            }
        }
    }
}

/// Menu item for checking updates
struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for updates on launch (after a brief delay to let the UI load)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // This triggers Sparkle's automatic update check
            // If an update is available, the user will be prompted
            NotificationCenter.default.post(name: NSNotification.Name("CheckForUpdatesOnLaunch"), object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Close all overlay windows before app terminates
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow || window is RecordingToolbarWindow || window is ResizingModalWindow {
                window.close()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit app when main window is closed
        return true
    }
}
