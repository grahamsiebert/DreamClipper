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
        // Hide the main window if we are starting in the toolbar-only mode
        // We defer slightly to let the window be created first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for window in NSApp.windows {
                // Determine if this is the main window (it won't be one of our special windows yet)
                // Actually, the main window is the only one at launch usually
                if !(window is RecordingOverlayWindow || window is SecondaryOverlayWindow || window is FloatingToolbarWindow) {
                    // Check if we should hide it
                    // effectively we hide all standard windows on launch
                    window.orderOut(nil)
                }
            }
        }
        
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit app when main window is closed
        return true
    }
}
