import SwiftUI

@main
struct DreamClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 800)
                .frame(width: 1280, height: 900)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request permissions on launch if needed, or handle setup
    }
}
