import SwiftUI
import Sparkle
import ApplicationServices

@main
struct DreamClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(updateManager)
                .frame(minWidth: 800, minHeight: 600)
                .frame(width: 1100, height: 750)
                .onAppear {
                    viewModel.updateManager = updateManager
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
    func applicationWillTerminate(_ notification: Notification) {
        // App termination logic is handled by the system mostly
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only hide the main window if both permissions are already granted.
        // When permissions are missing (e.g. fresh install), the main window must
        // stay visible so the user can see the OnboardingView to grant permissions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let hasAccessibility = AXIsProcessTrustedWithOptions(nil)
            let hasScreenRecording = CGPreflightScreenCaptureAccess()

            guard hasAccessibility && hasScreenRecording else { return }

            for window in NSApp.windows {
                if !(window is RecordingOverlayWindow || window is SecondaryOverlayWindow || window is FloatingToolbarWindow) {
                    window.orderOut(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false — the app hides its main window when using the floating toolbar.
        // Quit is handled explicitly via NSApp.terminate(nil) from the toolbar close button.
        return false
    }
}
