import Foundation
import ScreenCaptureKit
import ApplicationServices
import Cocoa

struct WindowInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let appName: String
    let frame: CGRect
    let pid: pid_t
    let ownerPid: Int32 // Added for app activation
    let scWindow: SCWindow? // Keep reference for recording
    var image: NSImage? // Thumbnail
}

class WindowManager: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasScreenRecordingPermission: Bool = false
    @Published var debugInfo: String = ""
    
    init() {
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }
    
    func checkAccessibilityPermission(prompt: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func checkScreenRecordingPermission() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }
    
    func requestScreenRecordingPermission() {
        // Use the official API to request screen capture access
        // This adds the app to the Screen Recording list in System Settings
        CGRequestScreenCaptureAccess()

        // Also trigger SCShareableContent to ensure the app appears in the list
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run {
                    checkScreenRecordingPermission()
                }
            } catch {
                print("Permission trigger failed (expected if denied): \(error)")
                await MainActor.run {
                    checkScreenRecordingPermission()
                }
            }
        }
    }
    
    @MainActor
    func fetchWindows() async {
        debugInfo = "Fetching windows..."
        print("Fetching windows...")
        
        do {
            let content = try await SCShareableContent.current
            let allWindows = content.windows
            print("Found \(allWindows.count) total windows via SCShareableContent.")
            debugInfo += "\nFound \(allWindows.count) total windows (SC)."
            
            // Log a few raw windows for debugging
            for (index, window) in allWindows.prefix(5).enumerated() {
                print("Window \(index): ID=\(window.windowID), Title='\(window.title ?? "nil")', App='\(window.owningApplication?.applicationName ?? "nil")', OnScreen=\(window.isOnScreen)")
            }
            
            var windows = allWindows.filter { window in
                // 1. Must be on screen
                guard window.isOnScreen else { return false }
                
                // 2. Must be a "normal" window (Layer 0)
                // This filters out menu bars, dock, notifications, overlays, etc.
                guard window.windowLayer == 0 else { return false }
                
                // 3. Minimum size to filter out cursors, status items, empty frames
                guard window.frame.width > 200 && window.frame.height > 200 else { return false }
                
                // 4. Exclude system apps and specific noise
                let excludedApps = [
                    "Control Center", "Dock", "Wallpaper", "Window Server",
                    "Notification Center", "SystemUIServer", "LoginWindow",
                    "ScreenSaverEngine", "Menubar", "Spotlight", "Display e Backstop",
                    "underbelly", "DreamClipper"
                ]
                if let appName = window.owningApplication?.applicationName, excludedApps.contains(appName) {
                    return false
                }
                
                // 5. Exclude windows with empty titles (unless it's a known app that might have empty titles but is useful)
                guard let title = window.title, !title.isEmpty else { return false }
                
                // 6. Exclude specific titles that are noise
                let excludedTitles = ["Menubar", "Desktop", "Window"]
                if excludedTitles.contains(title) { return false }
                
                return true
            }.compactMap { window -> WindowInfo? in
                let title = window.title ?? ""
                let appName = window.owningApplication?.applicationName ?? "Unknown"
                
                return WindowInfo(
                    id: Int(window.windowID),
                    name: title,
                    appName: appName,
                    frame: window.frame,
                    pid: window.owningApplication?.processID ?? 0,
                    ownerPid: window.owningApplication?.processID ?? 0,
                    scWindow: window,
                    image: nil
                )
            }
            
            // Fetch thumbnails
            for i in 0..<windows.count {
                if let scWindow = windows[i].scWindow {
                    if let image = await captureWindowImage(scWindow: scWindow) {
                        windows[i].image = image
                    }
                }
            }
            
            self.windows = windows
            print("After filtering: \(windows.count) windows.")
            debugInfo += "\n\(windows.count) windows after filtering."
            
            if windows.isEmpty {
                 debugInfo += "\nNo windows passed filter. Attempting fallback..."
                 fetchWindowsFallback()
            }
        } catch {
            print("Failed to fetch windows via SC: \(error)")
            debugInfo = "Error fetching windows (SC): \(error.localizedDescription)\nAttempting fallback..."
            fetchWindowsFallback()
        }
    }
    
    @MainActor
    func fetchWindowsFallback() {
        // Fallback using CGWindowList
        // Note: This API is older and might not have all permissions, but good for debugging.
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            debugInfo += "\nFallback failed: Could not get window list."
            return
        }
        
        debugInfo += "\nFallback found \(windowList.count) raw windows."
        
        let mappedWindows: [WindowInfo] = windowList.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? Int,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32 else {
                return nil
            }
            
            let name = dict[kCGWindowName as String] as? String ?? "[No Title]"
            let appName = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
            
            // Filter out small windows or system overlays
            if bounds.width < 50 || bounds.height < 50 { return nil }
            
            return WindowInfo(
                id: id,
                name: name,
                appName: appName,
                frame: bounds,
                pid: pid,
                ownerPid: pid,
                scWindow: nil, // No SCWindow in fallback
                image: nil
            )
        }
        
        // Fetch thumbnails for fallback
        // Note: SCScreenshotManager requires SCWindow, which we don't have in fallback.
        // We could try to find the matching SCWindow, but for now let's skip thumbnails in fallback mode.
        // Or we could use the deprecated API if we suppress warnings, but better to stay clean.
        
        self.windows = mappedWindows
        debugInfo += "\nFallback final count: \(mappedWindows.count)."
    }
    
    private func captureWindowImage(scWindow: SCWindow) async -> NSImage? {
        do {
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width)
            config.height = Int(scWindow.frame.height)
            config.showsCursor = false
            
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Failed to capture window image: \(error)")
            return nil
        }
    }
    
    @discardableResult
    func resizeWindow(_ window: WindowInfo) -> CGRect? {
        guard hasAccessibilityPermission else {
            print("ERROR: No accessibility permission")
            checkAccessibilityPermission()
            return nil
        }

        print("\n=== RESIZE WINDOW ATTEMPT ===")
        print("Target window: \(window.name)")
        print("Window app: \(window.appName)")
        print("Window PID: \(window.pid)")
        print("Window frame: \(window.frame)")

        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?

        // Get all windows for the app
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success, let windowsList = windowsRef as? [AXUIElement] {
            print("Found \(windowsList.count) windows for app")

            // Log all window titles for debugging
            for (index, axWin) in windowsList.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""
                print("  Window \(index): '\(title)'")
            }

            // Strategy 1: Try exact title match first
            for axWindow in windowsList {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""

                if title == window.name {
                    print("✓ Found exact title match: '\(title)'")
                    return resizeAXWindow(axWindow)
                }
            }

            // Strategy 2: For Preview, try matching just the filename (without extension)
            // Preview windows might have format: "filename.pdf - 1 page"
            print("No exact match, trying filename-based matching...")
            let windowBaseName = (window.name as NSString).deletingPathExtension
            for axWindow in windowsList {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""

                if title.contains(windowBaseName) || windowBaseName.contains(title) {
                    print("✓ Found filename match: '\(title)' contains '\(windowBaseName)'")
                    return resizeAXWindow(axWindow)
                }
            }

            // Strategy 3: Try matching by position
            print("No filename match, trying position-based matching...")
            for (index, axWindow) in windowsList.enumerated() {
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?

                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)

                var pos = CGPoint.zero
                var size = CGSize.zero

                if let posVal = posRef {
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                }
                if let sizeVal = sizeRef {
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
                }

                let axFrame = CGRect(origin: pos, size: size)
                print("  Window \(index) frame: \(axFrame)")

                // Check if this window frame matches our window frame (within tolerance)
                let tolerance: CGFloat = 10.0  // Increased tolerance
                if abs(axFrame.origin.x - window.frame.origin.x) < tolerance &&
                   abs(axFrame.origin.y - window.frame.origin.y) < tolerance &&
                   abs(axFrame.size.width - window.frame.width) < tolerance &&
                   abs(axFrame.size.height - window.frame.height) < tolerance {
                    print("✓ Found position match at: \(axFrame)")

                    // Get title for logging
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    print("  Window title: '\(title)'")

                    return resizeAXWindow(axWindow)
                }
            }

            // Strategy 4: If there's only one visible window, use it
            if windowsList.count == 1 {
                print("✓ Only one window available, using it")
                return resizeAXWindow(windowsList[0])
            }

            print("✗ Could not find matching window after trying all strategies")
        } else {
            print("✗ Failed to get windows for app, AX result code: \(result.rawValue)")
        }
        return nil
    }
    
    /// Calculates the optimal 16:9 window size based on screen dimensions
    /// Uses ~85% of available screen space while maintaining aspect ratio
    static func calculateTargetSize(for screen: NSScreen) -> CGSize {
        let visibleFrame = screen.visibleFrame
        let scaleFactor: CGFloat = 0.85

        let availableWidth = visibleFrame.width * scaleFactor
        let availableHeight = visibleFrame.height * scaleFactor

        // Calculate 16:9 dimensions that fit within available space
        let aspectRatio: CGFloat = 16.0 / 9.0

        // Try fitting to height first
        var targetHeight = availableHeight
        var targetWidth = targetHeight * aspectRatio

        // If width exceeds available width, fit to width instead
        if targetWidth > availableWidth {
            targetWidth = availableWidth
            targetHeight = targetWidth / aspectRatio
        }

        // Round to even numbers for video encoding compatibility
        targetWidth = floor(targetWidth / 2) * 2
        targetHeight = floor(targetHeight / 2) * 2

        return CGSize(width: targetWidth, height: targetHeight)
    }

    private func resizeAXWindow(_ axWindow: AXUIElement) -> CGRect? {
        // Check window role and subrole for debugging
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        print("Window role: \(role)")

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""
        print("Window subrole: \(subrole)")

        // Get Screen Size
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Calculate target size dynamically based on screen
        let targetSize = WindowManager.calculateTargetSize(for: screen)

        // Calculate menu bar height dynamically
        // visibleFrame excludes menu bar and dock (in Cocoa coordinates)
        // In Cocoa coords: origin at bottom-left, Y increases upward
        // Menu bar height = (top of full frame) - (top of visible frame)
        let menuBarHeightQuartz = screenFrame.maxY - visibleFrame.maxY

        print("Screen full frame: \(screenFrame)")
        print("Screen visible frame: \(visibleFrame)")
        print("Calculated menu bar height: \(menuBarHeightQuartz)")
        print("Dynamic target size: \(targetSize)")

        // Position at TOP of screen, just below menu bar (Quartz coordinates - Y=0 is top)
        // Center horizontally
        let x = (screenFrame.width - targetSize.width) / 2
        let y = menuBarHeightQuartz
        let targetOrigin = CGPoint(x: x, y: y)

        print("Target position: \(targetOrigin)")
        print("Target size: \(targetSize)")

        // Aggressive resize with multiple attempts
        var sizeValue = targetSize
        var positionValue = targetOrigin

        // Attempt 1: Position first, then size
        print("Attempt 1: Setting position...")
        if let positionRef = AXValueCreate(.cgPoint, &positionValue) {
            let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
            print("  Position set result: \(posResult.rawValue) (\(posResult == .success ? "SUCCESS" : "FAILED"))")
        }
        usleep(50000) // 0.05s

        print("Attempt 1: Setting size...")
        if let sizeRef = AXValueCreate(.cgSize, &sizeValue) {
            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeRef)
            print("  Size set result: \(sizeResult.rawValue) (\(sizeResult == .success ? "SUCCESS" : "FAILED"))")
        }
        usleep(100000) // 0.1s

        // Attempt 2: Size again, then position again
        print("Attempt 2: Setting size...")
        if let sizeRef = AXValueCreate(.cgSize, &sizeValue) {
            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeRef)
            print("  Size set result: \(sizeResult.rawValue)")
        }
        usleep(50000) // 0.05s

        print("Attempt 2: Setting position...")
        if let positionRef = AXValueCreate(.cgPoint, &positionValue) {
            let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
            print("  Position set result: \(posResult.rawValue)")
        }
        usleep(100000) // 0.1s

        // Attempt 3: Final size and position set
        print("Attempt 3: Setting size...")
        if let sizeRef = AXValueCreate(.cgSize, &sizeValue) {
            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeRef)
            print("  Size set result: \(sizeResult.rawValue)")
        }
        usleep(50000) // 0.05s

        print("Attempt 3: Setting position...")
        if let positionRef = AXValueCreate(.cgPoint, &positionValue) {
            let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
            print("  Position set result: \(posResult.rawValue)")
        }

        // Wait for window server and app to complete the resize
        usleep(250000) // 0.25s

        // 6. Verify and return actual position
        var actualPosValue: CFTypeRef?
        var actualSizeValue: CFTypeRef?

        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &actualPosValue)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &actualSizeValue)

        var actualPos = CGPoint.zero
        var actualSize = CGSize.zero

        if let posVal = actualPosValue {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &actualPos)
        }
        if let sizeVal = actualSizeValue {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &actualSize)
        }

        print("Resize attempt - Requested: \(targetSize), Got: \(actualSize)")

        // Return the actual frame in Quartz coordinates (Top-Left origin)
        if actualSize.width > 0 && actualSize.height > 0 {
             return CGRect(origin: actualPos, size: actualSize)
        }

        return nil
    }
}
