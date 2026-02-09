import Foundation
import SwiftUI
import AVKit
import Combine
import ScreenCaptureKit

indirect enum AppState: Equatable {
    case selection
    case resizing
    case recording
    case editing
    case exporting
    case done(exportedURL: URL)
    case help(context: HelpContext, previousState: AppState)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.selection, .selection): return true
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

        // Show resizing modal
        let modal = ResizingModalWindow()
        modal.contentView = NSHostingView(rootView: ResizingModalView(viewModel: self))
        modal.orderFront(nil)
        self.resizingModalWindow = modal

        // Hide main window
        NSApp.windows.first?.orderOut(nil)

        // Perform resize in background
        Task {
            // Attempt to resize the window via Accessibility API
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

                // Close resizing modal
                self.resizingModalWindow?.close()
                self.resizingModalWindow = nil

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
    var toolbarWindow: RecordingToolbarWindow?
    var resizingModalWindow: ResizingModalWindow?

    func showHelp(context: HelpContext) {
        // Store current state and transition to help
        let currentState = state
        state = .help(context: context, previousState: currentState)
    }

    func closeHelp() {
        // Return to previous state
        if case .help(_, let previousState) = state {
            state = previousState
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
        NSApp.windows.first?.orderOut(nil)

        // Show Overlay
        // SCWindow.frame uses Quartz display coordinates:
        //   - Origin at TOP-LEFT of the primary display
        //   - Y increases DOWNWARD
        // NSView/NSWindow use Cocoa coordinates:
        //   - Origin at BOTTOM-LEFT of each screen
        //   - Y increases UPWARD
        //
        // To convert from Quartz to Cocoa coordinates:
        //   1. Find which screen the window is on
        //   2. Convert coordinates relative to that screen's Cocoa coordinate space

        // Find which screen contains the window (or the screen with the most overlap)
        let targetScreen = findScreenForWindow(windowFrame: windowFrame)
        print("Target screen: \(targetScreen.frame)")

        // Convert window frame from Quartz to Cocoa coordinates
        let holeRect = convertQuartzToCocoa(quartzRect: windowFrame, targetScreen: targetScreen)
        print("Hole rect (Cocoa): \(holeRect)")

        let overlay = RecordingOverlayWindow(holeRect: holeRect, targetScreen: targetScreen)
        overlay.orderFrontAll()
        self.overlayWindow = overlay

        // Show Toolbar - position on the same screen as the window
        let toolbar = RecordingToolbarWindow()
        toolbar.contentView = NSHostingView(rootView: RecordingToolbarView(viewModel: self))
        // Position toolbar at bottom center of the target screen
        let screenFrame = targetScreen.visibleFrame
        let toolbarWidth: CGFloat = 220
        let toolbarHeight: CGFloat = 70
        let x = screenFrame.midX - (toolbarWidth / 2)
        let y = screenFrame.minY + 50 // Position near bottom of screen
        toolbar.setFrame(NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight), display: true)
        toolbar.orderFront(nil)
        self.toolbarWindow = toolbar

        // Bring selected window to front
        // We can't easily force another app's window to front without Accessibility API,
        // but we can try to activate the app.
        if let app = NSRunningApplication(processIdentifier: pid_t(window.ownerPid)) {
            app.activate()
        }
        
        Task {
            await screenRecorder.startRecording(window: scWindow)
            state = .recording
        }
    }
    
    func stopRecording() {
        // Close overlay immediately when stop is clicked
        overlayWindow?.closeAll()
        overlayWindow = nil
        toolbarWindow?.close()
        toolbarWindow = nil
        resizingModalWindow?.close()
        resizingModalWindow = nil

        // Show main window immediately
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
               window is RecordingToolbarWindow || window is ResizingModalWindow { continue }
            window.makeKeyAndOrderFront(nil)
        }

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
        // Close overlay immediately when discard is clicked
        overlayWindow?.closeAll()
        overlayWindow = nil
        toolbarWindow?.close()
        toolbarWindow = nil
        resizingModalWindow?.close()
        resizingModalWindow = nil

        // Show main window immediately
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
               window is RecordingToolbarWindow || window is ResizingModalWindow { continue }
            window.makeKeyAndOrderFront(nil)
        }

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
        state = .selection
        selectedWindow = nil
        recordedVideoURL = nil
        player = nil

        // Reset estimation state
        estimatedFileSizeString = "..."
        estimatedFileSizeMB = 0
        isCalculating = false
        showSizeWarning = false
        previousSizeMB = 0
        cachedResult = nil
        lastEstimationConfig = nil
    }

    /// Cleanup all overlay windows - call this when main window closes or app terminates
    func cleanupOverlays() {
        // First try normal cleanup through our references
        overlayWindow?.closeAll()
        overlayWindow = nil
        toolbarWindow?.close()
        toolbarWindow = nil
        resizingModalWindow?.close()
        resizingModalWindow = nil

        // Fallback: iterate through all app windows and close any orphaned overlays
        for window in NSApp.windows {
            if window is RecordingOverlayWindow || window is SecondaryOverlayWindow ||
               window is RecordingToolbarWindow || window is ResizingModalWindow {
                window.orderOut(nil)
                window.close()
            }
        }
    }

    // MARK: - Screen Detection and Coordinate Conversion

    /// Finds which screen contains the window (or has the most overlap with it)
    /// windowFrame is in Quartz coordinates (top-left origin)
    private func findScreenForWindow(windowFrame: CGRect) -> NSScreen {
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
    private func convertQuartzToCocoa(quartzRect: CGRect, targetScreen: NSScreen) -> CGRect {
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
