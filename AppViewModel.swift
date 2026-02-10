import Foundation
import SwiftUI
import AVKit
import Combine
import ScreenCaptureKit

indirect enum AppState: Equatable {
    case selection
    case picking       // Picker overlay is active, user hovering over windows
    case confirming    // Window selected, showing confirmation HUD
    case resizing
    case recording
    case editing
    case exporting
    case done(exportedURL: URL)
    case help(context: HelpContext, previousState: AppState)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.selection, .selection): return true
        case (.picking, .picking): return true
        case (.confirming, .confirming): return true
        case (.resizing, .resizing): return true
        case (.recording, .recording): return true
        case (.editing, .editing): return true
        case (.exporting, .exporting): return true
        case (.done, .done): return true
        case (.help, .help): return true
        default: return false
        }
    }
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var state: AppState = .selection

    @Published var windowManager = WindowManager()
    @Published var screenRecorder = ScreenRecorder()
    @Published var gifConverter = GifConverter()

    @Published var selectedWindow: WindowInfo?
    @Published var recordedVideoURL: URL?
    @Published var player: AVPlayer?

    @Published var trimStart: Double = 0.0
    @Published var trimEnd: Double = 0.0
    @Published var videoDuration: Double = 0.0

    @Published var targetFramerate: Int = 30
    @Published var resolution: GifResolution = .fullHD

    // Resize warning message
    @Published var resizeFailureMessage: String? = nil

    // Update manager (set from DreamClipperApp)
    var updateManager: UpdateManager?

    // Estimation State
    @Published private(set) var estimatedFileSizeString: String = "..."
    @Published private(set) var estimatedFileSizeMB: Double = 0
    @Published private(set) var isCalculating: Bool = false
    @Published var showSizeWarning: Bool = false

    private let estimator = GifConverter()
    private var estimationTask: Task<Void, Never>?
    private var cachedResult: GifResult?
    private var lastEstimationConfig: GifConfig?
    private var cancellables = Set<AnyCancellable>()
    private var previousSizeMB: Double = 0

    var estimatedFileSize: String {
        return estimatedFileSizeString
    }

    /// Size threshold constants
    static let sizeWarningThreshold: Double = 10.0  // MB - orange warning
    static let sizeDangerThreshold: Double = 15.0   // MB - red warning + tooltip
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Trigger estimation when any relevant parameter changes
        // Short debounce for responsive feedback while avoiding excessive recalculations
        Publishers.CombineLatest4($trimStart, $trimEnd, $targetFramerate, $recordedVideoURL)
            .combineLatest($resolution)
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.triggerEstimation()
            }
            .store(in: &cancellables)
    }
    
    func triggerEstimation() {
        estimationTask?.cancel()

        guard let source = recordedVideoURL, state == .editing else {
            estimatedFileSizeString = "..."
            estimatedFileSizeMB = 0
            isCalculating = false
            return
        }

        // Basic validation
        if trimEnd <= trimStart {
            estimatedFileSizeString = "--"
            estimatedFileSizeMB = 0
            isCalculating = false
            return
        }

        // Use sampling for estimation (every 3rd frame)
        let sampleFactor = 3

        let config = GifConfig(
            sourceURL: source,
            startTime: trimStart,
            endTime: trimEnd,
            frameRate: targetFramerate,
            resolution: resolution,
            sampleFactor: sampleFactor
        )

        estimatedFileSizeString = "Calculating..."
        isCalculating = true

        // Store current size before recalculating (for auto-dismiss logic)
        previousSizeMB = estimatedFileSizeMB

        estimationTask = Task {
            do {
                // Background estimation using memory sink
                // We use sampled encoding for speed
                let result = try await estimator.convert(config: config, output: .memory(NSMutableData()))

                if !Task.isCancelled {
                    // Extrapolate size: (sampledSize * sampleFactor)
                    // This is a rough estimate since we skipped frames.
                    // GIF compression with LZW works on frame deltas, so skipping frames
                    // affects compression ratios. We apply a correction factor to improve accuracy.
                    let estimatedBytes = Double(result.byteCount) * Double(sampleFactor) * 0.85
                    let sizeInMB = estimatedBytes / 1024.0 / 1024.0

                    let displayString: String
                    if sizeInMB < 1.0 {
                        displayString = String(format: "~%.0f KB", sizeInMB * 1024)
                    } else {
                        displayString = String(format: "~%.1f MB", sizeInMB)
                    }

                    self.estimatedFileSizeString = displayString
                    self.estimatedFileSizeMB = sizeInMB
                    self.isCalculating = false

                    // Auto-show warning if size exceeds danger threshold
                    if sizeInMB >= Self.sizeDangerThreshold {
                        self.showSizeWarning = true
                    }

                    // Auto-dismiss warning if size was reduced below danger threshold
                    if self.previousSizeMB >= Self.sizeDangerThreshold && sizeInMB < Self.sizeDangerThreshold {
                        self.showSizeWarning = false
                    }

                    // Since we used sampling, we CANNOT use this data for export.
                    self.cachedResult = nil
                    self.lastEstimationConfig = config
                }
            } catch {
                if !Task.isCancelled {
                    self.estimatedFileSizeString = "Error"
                    self.estimatedFileSizeMB = 0
                    self.isCalculating = false
                    DebugLogger.shared.log("Estimation failed: \(error)")
                }
            }
        }
    }
    
    func selectWindow(_ window: WindowInfo) {
        selectedWindow = window
    }
    
    func resizeSelectedWindow() {
        guard let window = selectedWindow else { return }

        // Attempt to resize and get the ACTUAL final frame from the window server
        // This is critical because the requested frame might be adjusted by the OS
        if let actualFrame = windowManager.resizeWindow(window) {
            // Update selectedWindow with the verified frame
            selectedWindow = WindowInfo(
                id: window.id,
                name: window.name,
                appName: window.appName,
                frame: actualFrame, // Use the verified frame!
                pid: window.pid,
                ownerPid: window.ownerPid,
                scWindow: window.scWindow,
                image: window.image
            )
        } else {
            // Fallback: If resize verification failed (e.g. permission issue),
            // calculate the theoretical frame so we at least try to match what we asked for.
            if let screen = NSScreen.main {
                // Use dynamic target size calculation
                let targetSize = WindowManager.calculateTargetSize(for: screen)

                // Calculate menu bar height dynamically
                let menuBarHeightQuartz = screen.frame.maxY - screen.visibleFrame.maxY

                let x = (screen.frame.width - targetSize.width) / 2
                let y = menuBarHeightQuartz

                let theoreticalFrame = CGRect(origin: CGPoint(x: x, y: y), size: targetSize)

                selectedWindow = WindowInfo(
                    id: window.id,
                    name: window.name,
                    appName: window.appName,
                    frame: theoreticalFrame,
                    pid: window.pid,
                    ownerPid: window.ownerPid,
                    scWindow: window.scWindow,
                    image: window.image
                )
            }
        }
    }

    func startRecordingWithResize() {
        guard let window = selectedWindow else { return }

        print("Starting resize and record flow for window: \(window.name)")
        print("Initial window frame: \(window.frame)")

        // Switch toolbar to resizing phase (toolbar already visible)
        toolbarPhase = .resizing

        // Ensure main window is hidden
        hideMainWindow()

        // Perform resize in background
        Task {
            // Step 1: Exit full-screen if the window is in native macOS full-screen mode
            // Must happen BEFORE activate/resize — full-screen exit destroys the Space
            let wasFullScreen = windowManager.exitFullScreenIfNeeded(window)
            if wasFullScreen {
                // Full-screen exit animation + Space destruction takes ~2s
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            // Step 2: Raise the specific target window to make it the app's frontmost window
            // This works cross-Space and ensures activate() switches to the correct Space
            windowManager.raiseWindow(window)

            // Step 3: Activate the target app — macOS will switch to the Space
            // where the raised (frontmost) window lives
            if let app = NSRunningApplication(processIdentifier: pid_t(window.ownerPid)) {
                app.activate(options: [.activateIgnoringOtherApps])
            }

            // Step 4: Wait for Space transition animation (~1s)
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // Step 5: Resize the window via Accessibility API
            let requestedFrame = windowManager.resizeWindow(window)
            print("Resize requested, got frame: \(requestedFrame?.debugDescription ?? "nil")")

            // Wait for window server and app to complete resize animation
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

            // Re-fetch the window from ScreenCaptureKit to get actual current frame
            let updatedWindow = await refetchWindow(window)

            await MainActor.run {
                if let updated = updatedWindow {
                    // Verify the window is actually 16:9 (within tolerance)
                    let aspectRatio = updated.frame.width / updated.frame.height
                    let target169 = 16.0 / 9.0
                    let tolerance = 0.05 // 5% tolerance

                    print("Window aspect ratio: \(aspectRatio), target: \(target169)")

                    if abs(aspectRatio - target169) > tolerance {
                        // Window could not be resized to 16:9
                        self.resizeFailureMessage = "Window could not be resized to 16:9. Recording will use current window size."
                        print("WARNING: \(self.resizeFailureMessage!)")
                    } else {
                        self.resizeFailureMessage = nil
                        print("Window successfully resized to 16:9")
                    }

                    // Update selectedWindow with verified frame
                    self.selectedWindow = updated
                    print("Updated selected window with frame: \(updated.frame)")
                } else {
                    print("CRITICAL: Could not refetch window from ScreenCaptureKit")
                    if let requested = requestedFrame {
                        print("Using fallback frame from AX API: \(requested)")
                        // Need to refetch to get the updated SCWindow object
                        // Using the old scWindow may have stale coordinates
                    } else {
                        print("ERROR: No frame information available")
                    }
                }
            }

            // If there's a warning message, show it for 2 seconds
            if resizeFailureMessage != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }

            // CRITICAL: Re-fetch one more time just before recording to ensure we have
            // the absolute latest window coordinates
            let finalWindow = await refetchWindow(window)

            await MainActor.run {
                if let final = finalWindow {
                    self.selectedWindow = final
                    print("Final pre-recording window frame: \(final.frame)")
                }

                // Switch toolbar to recording phase
                self.toolbarPhase = .recording

                // Now start recording with updated window frame
                print("Starting recording NOW")
                self.startRecording()
            }
        }
    }

    /// Re-fetches a specific window from ScreenCaptureKit to get its current frame
    private func refetchWindow(_ window: WindowInfo) async -> WindowInfo? {
        do {
            let content = try await SCShareableContent.current

            // Find the window by ID
            if let scWindow = content.windows.first(where: { Int($0.windowID) == window.id }) {
                print("Refetched window - Frame: \(scWindow.frame)")
                return WindowInfo(
                    id: window.id,
                    name: scWindow.title ?? window.name,
                    appName: window.appName,
                    frame: scWindow.frame, // Updated frame from SCWindow
                    pid: window.pid,
                    ownerPid: window.ownerPid,
                    scWindow: scWindow,
                    image: window.image
                )
            } else {
                print("Failed to find window with ID: \(window.id)")
            }
        } catch {
            print("Failed to refetch window: \(error)")
        }
        return nil
    }

    var overlayWindow: RecordingOverlayWindow?
    var floatingToolbarWindow: FloatingToolbarWindow?

    // Picker windows
    var pickerOverlayWindows: [WindowPickerOverlayWindow] = []

    @Published var toolbarPhase: ToolbarPhase = .ready
    @Published var hoveredWindowInfo: WindowManager.CursorWindowInfo?

    func showHelp(context: HelpContext) {
        // If we are in picking mode, cancel it so we return to "Ready" state
        if state == .picking {
            cancelPicker()
        }
        
        // Store current state and transition to help
        let currentState = state
        state = .help(context: context, previousState: currentState)
        
        // Show main window to display help
        showMainWindow()
    }

    func closeHelp() {
        // Return to previous state
        if case .help(_, let previousState) = state {
            state = previousState
            
            // If returning to a toolbar-only state, hide the main window again
            if [.selection, .picking].contains(state) {
                hideMainWindow()
            }
        }
    }

    func startRecording() {
        guard let window = selectedWindow, let scWindow = window.scWindow else { return }

        print("=== STARTRECORDING ===")
        print("selectedWindow.frame: \(window.frame)")
        print("scWindow.frame: \(scWindow.frame)")

        // CRITICAL: Use the SCWindow's current frame, not the cached one
        // The scWindow object gets updated by the system
        let windowFrame = scWindow.frame
        print("Using windowFrame: \(windowFrame)")

        // Hide main window
        hideMainWindow()

        // Show Overlay
        let targetScreen = findScreenForWindow(windowFrame: windowFrame)
        print("Target screen: \(targetScreen.frame)")

        let holeRect = convertQuartzToCocoa(quartzRect: windowFrame, targetScreen: targetScreen)
        print("Hole rect (Cocoa): \(holeRect)")

        let overlay = RecordingOverlayWindow(holeRect: holeRect, targetScreen: targetScreen)
        overlay.orderFrontAll()
        self.overlayWindow = overlay

        // Switch toolbar to recording phase
        toolbarPhase = .recording
        // Toolbar is already shown from picker flow — just ensure it's visible
        floatingToolbarWindow?.orderFront(nil)

        // Bring selected window to front
        if let app = NSRunningApplication(processIdentifier: pid_t(window.ownerPid)) {
            app.activate()
        }
        
        Task {
            await screenRecorder.startRecording(window: scWindow)
            state = .recording
        }
    }
    
    func stopRecording() {
        // Close overlay and toolbar immediately
        overlayWindow?.closeAll()
        overlayWindow = nil
        closeFloatingToolbar()

        // Show main window immediately
        showMainWindow()

        Task {
            await screenRecorder.stopRecording()

            if let url = screenRecorder.recordingURL {
                self.recordedVideoURL = url
                self.setupPlayer(url: url)
                state = .editing
            }
        }
    }
    
    func pauseRecording() {
        screenRecorder.pause()
    }
    
    func resumeRecording() {
        screenRecorder.resume()
    }
    
    func discardRecording() {
        // Close overlay and toolbar immediately
        overlayWindow?.closeAll()
        overlayWindow = nil
        closeFloatingToolbar()

        // Show main window immediately
        showMainWindow()

        Task {
            await screenRecorder.discard()
            reset()
        }
    }
    
    private var timeObserver: Any?
    
    func setupPlayer(url: URL) {
        DebugLogger.shared.log("AppViewModel: Setting up player with URL: \(url.path)")
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        
        Task {
            do {
                videoDuration = try await asset.load(.duration).seconds
                DebugLogger.shared.log("AppViewModel: Video duration loaded: \(videoDuration)")
                trimStart = 0
                trimEnd = videoDuration
                
                await MainActor.run {
                    startPlaybackLoop()
                    player?.play()
                }
            } catch {
                DebugLogger.shared.log("AppViewModel: Failed to load video duration: \(error)")
            }
        }
    }
    
    func startPlaybackLoop() {
        stopPlaybackLoop()
        
        // Loop every 0.1s to check if we passed trimEnd
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                if time.seconds >= self.trimEnd {
                    self.seek(to: self.trimStart)
                    self.player?.play()
                } else if time.seconds < self.trimStart {
                     self.seek(to: self.trimStart)
                }
            }
        }
    }
    
    func stopPlaybackLoop() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    func pauseForScrubbing() {
        player?.pause()
    }
    
    func resumeAfterScrubbing() {
        seek(to: trimStart)
        player?.play()
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func exportGif() {
        guard let source = recordedVideoURL else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "recording.gif"
        
        panel.begin { response in
            if response == .OK, let target = panel.url {
                self.state = .exporting
                self.stopPlaybackLoop()
                self.player?.pause()
                
                Task {
                    // Full Encoding for Export (no sampling, no cache used if sampling was enabled)
                    let currentConfig = GifConfig(
                        sourceURL: source, 
                        startTime: self.trimStart, 
                        endTime: self.trimEnd, 
                        frameRate: self.targetFramerate,
                        resolution: self.resolution,
                        sampleFactor: 1 // ALWAYS FULL QUALITY
                    )
                    
                    // We skip the cache check because estimation now uses sampling,
                    // so the cached data is incomplete/invalid for final export.
                    DebugLogger.shared.log("Starting full export encode...")

                    do {
                        let _ = try await self.gifConverter.convert(config: currentConfig, output: .file(target))
                        await MainActor.run { self.state = .done(exportedURL: target) }
                    } catch {
                        // On error, go back to editing
                        await MainActor.run { self.state = .editing }
                    }
                }
            }
        }
    }
    
    func reset() {
        stopPlaybackLoop()
        cleanupOverlays()
        
        // Reset to initial ready state
        state = .selection
        toolbarPhase = .ready
        showFloatingToolbar()
        
        selectedWindow = nil
        recordedVideoURL = nil
        player = nil
        hoveredWindowInfo = nil

        // Reset estimation state
        estimatedFileSizeString = "..."
        estimatedFileSizeMB = 0
        isCalculating = false
        showSizeWarning = false
        previousSizeMB = 0
        cachedResult = nil
        lastEstimationConfig = nil
    }

    // MARK: - Floating Toolbar Helpers

    /// Creates and shows the unified floating toolbar at bottom-center of screen
    /// Creates and shows the unified floating toolbar
    func showFloatingToolbar() {
        if floatingToolbarWindow == nil {
            let toolbar = FloatingToolbarWindow()
            toolbar.contentView = NSHostingView(rootView: FloatingToolbarView(viewModel: self))
            toolbar.positionOnScreen() // Use new helper for full-width positioning
            toolbar.orderFront(nil)
            self.floatingToolbarWindow = toolbar
        } else {
            floatingToolbarWindow?.orderFront(nil)
        }
    }

    /// Closes and releases the floating toolbar
    func closeFloatingToolbar() {
        floatingToolbarWindow?.orderOut(nil)
        floatingToolbarWindow?.close()
        floatingToolbarWindow = nil
    }

    // MARK: - Main Window Helpers

    /// Hides the main app window (used when entering picker/recording flow)
    func hideMainWindow() {
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
               window is FloatingToolbarWindow || window is WindowPickerOverlayWindow { continue }
            window.orderOut(nil)
        }
    }

    /// Shows the main app window (used when returning from picker/recording flow)
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
               window is FloatingToolbarWindow || window is WindowPickerOverlayWindow { continue }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Cleanup all overlay windows - call this when main window closes or app terminates
    func cleanupOverlays() {
        // First try normal cleanup through our references
        overlayWindow?.closeAll()
        overlayWindow = nil
        closeFloatingToolbar()

        // Picker windows
        for window in pickerOverlayWindows {
            window.orderOut(nil)
            window.close()
        }
        pickerOverlayWindows.removeAll()

        // Fallback: iterate through all app windows and close any orphaned overlays
        for window in NSApp.windows {
             if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
                window is FloatingToolbarWindow ||
                window is WindowPickerOverlayWindow {
                 window.orderOut(nil)
                 window.close()
             }
        }
    }

    // MARK: - Window Picker Flow

    func startPicking() {
        state = .picking
        hoveredWindowInfo = nil
        toolbarPhase = .picking

        // Hide main window
        hideMainWindow()

        // Create and show picker overlays (one per screen)
        for screen in NSScreen.screens {
            let overlay = WindowPickerOverlayWindow(screen: screen)
            overlay.pickerView.onMouseMoved = { [weak self, weak overlay] locationInView in
                guard let overlay = overlay else { return nil }
                return self?.pickerMouseMoved(at: locationInView, in: overlay)
            }
            overlay.pickerView.onMouseClicked = { [weak self] in
                self?.pickerMouseClicked()
            }
            overlay.pickerView.onMouseExited = { [weak self] in
                self?.hoveredWindowInfo = nil
            }
            overlay.orderFront(nil)
            self.pickerOverlayWindows.append(overlay)
        }

        // Create and show the floating toolbar
        showFloatingToolbar()
    }

    /// Called by the overlay NSView on mouseMoved. Returns the highlight rect in Cocoa coordinates for drawing.
    func pickerMouseMoved(at locationInView: NSPoint, in overlayWindow: WindowPickerOverlayWindow) -> CGRect? {
        // No need to guard pickerOverlayWindow here as we pass it in

        // Convert NSView point to screen coordinates (Cocoa)
        let screenPoint = overlayWindow.convertPoint(toScreen: locationInView)

        // Convert to Quartz coordinates for CGWindowList lookup
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let quartzY = primaryScreen.frame.height - screenPoint.y
        let quartzPoint = CGPoint(x: screenPoint.x, y: quartzY)

        // Find window under cursor
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let info = windowManager.windowUnderCursor(at: quartzPoint, excludingPIDs: [ownPID]) else {
            hoveredWindowInfo = nil
            return nil
        }

        hoveredWindowInfo = info

        // Convert the window's Quartz frame to Cocoa coordinates for the overlay to draw
        let targetScreen = findScreenForWindow(windowFrame: info.frame)
        let cocoaRect = convertQuartzToCocoa(quartzRect: info.frame, targetScreen: targetScreen)

        // Convert from global screen coordinates to the overlay window's view coordinates
        let viewOrigin = overlayWindow.convertPoint(fromScreen: cocoaRect.origin)
        return CGRect(origin: viewOrigin, size: cocoaRect.size)
    }

    /// Called by the overlay NSView on mouseDown.
    func pickerMouseClicked() {
        guard let info = hoveredWindowInfo else { return }

        // Close all picker overlays
        for window in pickerOverlayWindows {
            window.orderOut(nil)
            window.close()
        }
        pickerOverlayWindows.removeAll()

        // Fetch the SCWindow reference and build WindowInfo
        Task {
            if let windowInfo = await windowManager.fetchSCWindowForCGWindow(info) {
                self.selectedWindow = windowInfo
            } else {
                // Fallback: create WindowInfo without SCWindow (will try to match later)
                self.selectedWindow = WindowInfo(
                    id: info.windowID,
                    name: info.title,
                    appName: info.appName,
                    frame: info.frame,
                    pid: info.ownerPID,
                    ownerPid: info.ownerPID,
                    scWindow: nil,
                    image: nil
                )
            }

            // Switch toolbar to confirm phase (smooth transition in-place)
            self.toolbarPhase = .confirmWindow
            self.state = .confirming
        }
    }

    /// Called from the confirmation HUD to start recording.
    func startRecordingFromPicker(resize: Bool) {
        // Toolbar stays visible — phase will change in startRecordingWithResize/startRecording
        if resize {
            startRecordingWithResize()
        } else {
            startRecording()
        }
    }

    /// Cancels the picker and sets toolbar to ready state.
    func cancelPicker() {
        // Close all picker overlays, but keep toolbar visible
        for window in pickerOverlayWindows {
            window.orderOut(nil)
            window.close()
        }
        pickerOverlayWindows.removeAll()
        
        // Reset state
        hoveredWindowInfo = nil
        selectedWindow = nil
        state = .selection
        toolbarPhase = .ready
        
        // Ensure main window is hidden (we are using toolbar as main UI now)
        hideMainWindow()
        
        // Ensure toolbar is visible
        showFloatingToolbar()
    }

    // MARK: - Screen Detection and Coordinate Conversion

    /// Finds which screen contains the window (or has the most overlap with it)
    /// windowFrame is in Quartz coordinates (top-left origin)
    func findScreenForWindow(windowFrame: CGRect) -> NSScreen {
        guard let primaryScreen = NSScreen.screens.first else {
            return NSScreen.main ?? NSScreen.screens.first!
        }

        print("Finding screen for window frame (Quartz): \(windowFrame)")
        print("Available screens:")
        for (idx, screen) in NSScreen.screens.enumerated() {
            print("  Screen \(idx): \(screen.frame)")
        }

        // Simple approach: check window's center point
        // Window is in Quartz coords (top-left origin, Y down)
        // Screens are in Cocoa coords (bottom-left origin, Y up)
        // But all screens share the same coordinate space

        // Convert window center from Quartz to Cocoa
        let windowCenterQuartz = CGPoint(
            x: windowFrame.origin.x + windowFrame.width / 2,
            y: windowFrame.origin.y + windowFrame.height / 2
        )

        // Convert Y coordinate from Quartz (top-left) to Cocoa (bottom-left)
        let primaryScreenHeight = primaryScreen.frame.height
        let windowCenterCocoa = CGPoint(
            x: windowCenterQuartz.x,
            y: primaryScreenHeight - windowCenterQuartz.y
        )

        print("Window center (Quartz): \(windowCenterQuartz)")
        print("Window center (Cocoa): \(windowCenterCocoa)")

        // Find which screen contains this point
        for screen in NSScreen.screens {
            if screen.frame.contains(windowCenterCocoa) {
                print("Found screen: \(screen.frame)")
                return screen
            }
        }

        // Fallback: use main screen
        print("No screen contains window center, using main screen")
        return NSScreen.main ?? primaryScreen
    }

    /// Converts a rectangle from Quartz coordinates to Cocoa coordinates
    /// - Parameters:
    ///   - quartzRect: Rectangle in Quartz coordinates (origin at top-left of primary display, Y down)
    ///   - targetScreen: The screen that will contain the converted rectangle (not currently used, kept for API compatibility)
    /// - Returns: Rectangle in Cocoa coordinates (origin at bottom-left, Y up)
    func convertQuartzToCocoa(quartzRect: CGRect, targetScreen: NSScreen) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return quartzRect
        }

        // Quartz (CGWindow) coordinates:
        //   - Origin at top-left of primary screen
        //   - Y increases downward
        //
        // Cocoa (NSWindow) coordinates:
        //   - Origin at bottom-left of primary screen
        //   - Y increases upward
        //   - All screens share this same coordinate space
        //
        // Conversion formula:
        //   cocoaY = primaryScreenHeight - quartzY - windowHeight

        let primaryScreenHeight = primaryScreen.frame.height
        let cocoaY = primaryScreenHeight - quartzRect.origin.y - quartzRect.height
        let cocoaX = quartzRect.origin.x // X coordinate is the same

        let cocoaRect = CGRect(x: cocoaX, y: cocoaY, width: quartzRect.width, height: quartzRect.height)

        print("Coordinate conversion:")
        print("  Quartz: \(quartzRect)")
        print("  Cocoa:  \(cocoaRect)")
        print("  Primary screen height: \(primaryScreenHeight)")

        return cocoaRect
    }
}
