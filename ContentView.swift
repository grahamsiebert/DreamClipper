import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            if !viewModel.windowManager.hasAccessibilityPermission || !viewModel.windowManager.hasScreenRecordingPermission {
                OnboardingView(windowManager: viewModel.windowManager)
            } else {
                VStack {
                    switch viewModel.state {
                    case .selection:
                        SelectionView(viewModel: viewModel, windowManager: viewModel.windowManager)
                    case .resizing:
                        ResizingView(viewModel: viewModel)
                    case .recording:
                        RecordingView(viewModel: viewModel, screenRecorder: viewModel.screenRecorder)
                    case .editing:
                        EditingView(viewModel: viewModel)
                    case .exporting:
                        ExportingView(viewModel: viewModel, gifConverter: viewModel.gifConverter)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
    }
}

struct OnboardingView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var currentStep = 0
    @State private var permissionTimer: Timer?

    var body: some View {
        VStack(spacing: 40) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.accent)
                
                Text("Welcome to DreamClipper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.text)
                
                Text("To get started, we need a few permissions to capture your screen.")
                    .font(.title3)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Steps
            VStack(spacing: 24) {
                // Step 1: Accessibility
                OnboardingStep(
                    icon: "hand.raised.fill",
                    title: "Accessibility Permission",
                    description: "Required to resize windows to 1080p.",
                    isCompleted: windowManager.hasAccessibilityPermission,
                    isActive: !windowManager.hasAccessibilityPermission
                ) {
                    windowManager.checkAccessibilityPermission(prompt: true)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                // Step 2: Screen Recording
                OnboardingStep(
                    icon: "video.fill",
                    title: "Screen Recording Permission",
                    description: "Required to capture the window content.",
                    isCompleted: windowManager.hasScreenRecordingPermission,
                    isActive: windowManager.hasAccessibilityPermission && !windowManager.hasScreenRecordingPermission
                ) {
                    windowManager.requestScreenRecordingPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(32)
            .background(Theme.surface)
            .cornerRadius(16)
            .frame(maxWidth: 600)
            
            // Footer
            if windowManager.hasAccessibilityPermission && windowManager.hasScreenRecordingPermission {
                Button(action: {
                    // Just trigger a refresh to be sure
                    Task { await windowManager.fetchWindows() }
                }) {
                    Text("Get Started")
                        .fontWeight(.bold)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Theme.accentGradient)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(permissionTimer != nil ? 360 : 0))
                        .animation(
                            permissionTimer != nil ?
                                Animation.linear(duration: 2.0).repeatForever(autoreverses: false) :
                                .default,
                            value: permissionTimer != nil
                        )
                    Text("Monitoring permissions...")
                }
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
            }
        }
        .padding()
        .onAppear {
            startPermissionMonitoring()
        }
        .onDisappear {
            stopPermissionMonitoring()
        }
    }

    private func startPermissionMonitoring() {
        // Initial check
        windowManager.checkAccessibilityPermission(prompt: false)
        windowManager.checkScreenRecordingPermission()

        // Start faster polling (0.3s instead of 1.0s) for quicker response
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            windowManager.checkAccessibilityPermission(prompt: false)
            windowManager.checkScreenRecordingPermission()

            // Auto-stop timer when both permissions are granted
            if windowManager.hasAccessibilityPermission && windowManager.hasScreenRecordingPermission {
                stopPermissionMonitoring()
            }
        }
    }

    private func stopPermissionMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

struct OnboardingStep: View {
    let icon: String
    let title: String
    let description: String
    let isCompleted: Bool
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? Theme.accent : Color.gray.opacity(0.3)))
                    .frame(width: 48, height: 48)
                
                Image(systemName: isCompleted ? "checkmark" : icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isActive || isCompleted ? Theme.text : Theme.textSecondary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            
            Spacer()
            
            if !isCompleted {
                Button(action: action) {
                    Text("Open Settings")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isActive ? Theme.accent.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(isActive ? Theme.accent : Color.gray)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
        .opacity(isActive || isCompleted ? 1.0 : 0.5)
    }
}

struct SelectionView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var windowManager: WindowManager
    
    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 20)
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Select a Window")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(action: {
                    Task { await windowManager.fetchWindows() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            

            
            // Window Grid
            ScrollView {
                if windowManager.windows.isEmpty {
                    EmptyStateView(debugInfo: windowManager.debugInfo)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(windowManager.windows) { window in
                            WindowCard(window: window, isSelected: viewModel.selectedWindow == window)
                                .onTapGesture {
                                    viewModel.selectWindow(window)
                                }
                        }
                    }
                    .padding()
                }
            }
            
            // Footer Actions
            if let _ = viewModel.selectedWindow {
                Button(action: {
                    viewModel.startRecordingWithResize()
                }) {
                    Text("Start Recording")
                        .fontWeight(.bold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Theme.accentGradient)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: Theme.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .padding(.top)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            Task { await windowManager.fetchWindows() }
        }
    }
}

struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Color.black
                if let image = window.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundColor(Theme.textSecondary)
                }
                
                if isSelected {
                    ZStack {
                        Color.black.opacity(0.3)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            .frame(height: 140)
            .background(Color.black)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(window.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(window.name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}



struct EmptyStateView: View {
    let debugInfo: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(Theme.textSecondary.opacity(0.5))
            
            Text("No windows found")
                .font(.title2)
                .foregroundColor(Theme.textSecondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug Info:")
                    .font(.caption)
                    .bold()
                    .foregroundColor(Theme.textSecondary)
                
                Text(debugInfo)
                    .font(.caption2)
                    .monospaced()
                    .foregroundColor(Theme.textSecondary)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
            }
            .padding(.top)
        }
        .padding(40)
    }
}

struct ResizingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 80, height: 80)
                    .pulseEffect()
            }

            VStack(spacing: 8) {
                Text("Resizing Window")
                    .font(.title)
                    .foregroundColor(Theme.text)

                if let message = viewModel.resizeFailureMessage {
                    Text(message)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text("Adjusting to 16:9 aspect ratio...")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}

struct RecordingView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var screenRecorder: ScreenRecorder

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .pulseEffect()
            }

            VStack(spacing: 8) {
                Text("Recording in Progress")
                    .font(.title)
                    .foregroundColor(Theme.text)

                if let error = screenRecorder.error {
                    Text(error)
                        .foregroundColor(.red)
                } else {
                    Text("Capture whatever you need...")
                        .foregroundColor(Theme.textSecondary)
                }
            }

            Button(action: {
                viewModel.stopRecording()
            }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
                .fontWeight(.bold)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

struct EditingView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHoveringDiscard = false
    @State private var isHoveringExport = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Edit Recording")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Video Preview & Timeline Card
            VStack(spacing: 0) {
                // Video Player
                GeometryReader { geometry in
                    ZStack {
                        Color.black
                        
                        if let player = viewModel.player {
                            PlayerView(player: player)
                                // Let the player fit naturally within the available space
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 8
                    )
                )
                .clipped()
                
                Divider()
                    .background(Theme.border)
                
                // Timeline
                TimelineView(viewModel: viewModel)
                    .frame(height: 60)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Theme.surface)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 0
                        )
                    )
            }
            .background(Theme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.horizontal)
            
            // Controls & Actions Bar
            HStack(spacing: 24) {
                // Settings Group using Grid for perfect alignment
                Grid(horizontalSpacing: 24, verticalSpacing: 0) {
                    GridRow {
                        // Framerate Column
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Framerate")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                                .textCase(.uppercase)
                                .fixedSize() // Prevent wrapping
                            
                            Picker("Framerate", selection: $viewModel.targetFramerate) {
                                Text("15").tag(15)
                                Text("30").tag(30)
                                Text("60").tag(60)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140) // Slightly wider
                            .labelsHidden()
                        }
                        
                        // Resolution Column
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Resolution")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                                .textCase(.uppercase)
                                .fixedSize() // Prevent wrapping
                            
                            Picker("Resolution", selection: $viewModel.resolution) {
                                Text("1080p").tag(GifResolution.fullHD)
                                Text("720p").tag(GifResolution.hd)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140) // Slightly wider
                            .labelsHidden()
                        }
                    }
                }
                
                Spacer()
                
                // Estimated Size
                HStack(spacing: 12) {
                    Divider().frame(height: 30)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ESTIMATED SIZE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize()
                        
                        Text(viewModel.estimatedFileSize)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accentGradient)
                            .fixedSize()
                    }
                    
                    Divider().frame(height: 30)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    // Discard
                    Button(action: {
                        viewModel.reset()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                            Text("Discard")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(isHoveringDiscard ? Theme.text : Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isHoveringDiscard ? Theme.surfaceHover : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle()) // Better hover detection
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringDiscard = $0 }
                    
                    // Export
                    Button(action: {
                        viewModel.exportGif()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: 14))
                            Text("Export GIF")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Theme.accentGradient)
                        .cornerRadius(8)
                        .shadow(color: Theme.accent.opacity(isHoveringExport ? 0.4 : 0.2), radius: isHoveringExport ? 8 : 4, x: 0, y: 2)
                        .scaleEffect(isHoveringExport ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringExport)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringExport = $0 }
                }
            }
            .padding(20)
            .background(Theme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}

// Helper for rounding specific corners removed as we use UnevenRoundedRectangle now


struct TimelineView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingRange = false
    @State private var dragStartOffset: CGFloat = 0
    
    private let timelineHeight: CGFloat = 56
    private let handleWidth: CGFloat = 18
    
    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width - 40 // Account for padding
            
            VStack(spacing: 8) {
                // Time labels row
                HStack {
                    // Start time
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 9, weight: .semibold))
                        Text(formatTime(viewModel.trimStart))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.accent)
                    
                    Spacer()
                    
                    // Duration (center)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 9, weight: .medium))
                        Text(formatTime(viewModel.trimEnd - viewModel.trimStart))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceHover)
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    // End time
                    HStack(spacing: 4) {
                        Text(formatTime(viewModel.trimEnd))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 4)
                
                // Timeline track
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.background)
                        .frame(height: 36)
                    
                    // Excluded regions (before start and after end)
                    HStack(spacing: 0) {
                        // Before start (dimmed)
                        if startPosition(in: trackWidth) > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: startPosition(in: trackWidth))
                        }
                        
                        // Selected region - draggable to move entire range
                        Rectangle()
                            .fill(Theme.accent.opacity(isDraggingRange ? 0.25 : 0.15))
                            .frame(width: selectedWidth(in: trackWidth))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Theme.accent, lineWidth: isDraggingRange ? 3 : 2)
                            )
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isDraggingRange {
                                            isDraggingRange = true
                                            // Store the initial offset from the start of the selection
                                            dragStartOffset = value.startLocation.x
                                            viewModel.pauseForScrubbing()
                                        }
                                        
                                        // Calculate the new position based on drag
                                        let duration = viewModel.trimEnd - viewModel.trimStart
                                        let dragDelta = value.location.x - dragStartOffset
                                        let currentStartPos = startPosition(in: trackWidth)
                                        let newStartPos = currentStartPos + dragDelta
                                        
                                        // Convert position to time
                                        let newStartPercentage = newStartPos / trackWidth
                                        var newStart = viewModel.videoDuration * newStartPercentage
                                        
                                        // Clamp to valid range
                                        newStart = max(0, min(viewModel.videoDuration - duration, newStart))
                                        let newEnd = newStart + duration
                                        
                                        viewModel.trimStart = newStart
                                        viewModel.trimEnd = newEnd
                                        viewModel.seek(to: newStart)
                                        
                                        // Update the offset for continuous dragging
                                        dragStartOffset = value.location.x
                                    }
                                    .onEnded { _ in
                                        isDraggingRange = false
                                        viewModel.resumeAfterScrubbing()
                                    }
                            )
                        
                        // After end (dimmed)
                        if endPosition(in: trackWidth) > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: endPosition(in: trackWidth))
                        }
                    }
                    .frame(height: 36)
                    .cornerRadius(6)
                    .clipped()
                    
                    // Start handle
                    TrimHandle(isStart: true, isDragging: isDraggingStart)
                        .offset(x: startPosition(in: trackWidth) - handleWidth / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingStart {
                                        isDraggingStart = true
                                        viewModel.pauseForScrubbing()
                                    }
                                    let x = value.location.x
                                    let percentage = x / trackWidth
                                    let newValue = viewModel.videoDuration * max(0, min(1, percentage))
                                    viewModel.trimStart = min(newValue, viewModel.trimEnd - 0.1)
                                    viewModel.seek(to: viewModel.trimStart)
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                    viewModel.resumeAfterScrubbing()
                                }
                        )
                        .zIndex(1) // Ensure handles are above the draggable region
                    
                    // End handle
                    TrimHandle(isStart: false, isDragging: isDraggingEnd)
                        .offset(x: startPosition(in: trackWidth) + selectedWidth(in: trackWidth) - handleWidth / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingEnd {
                                        isDraggingEnd = true
                                        viewModel.pauseForScrubbing()
                                    }
                                    let x = value.location.x
                                    let percentage = x / trackWidth
                                    let newValue = viewModel.videoDuration * max(0, min(1, percentage))
                                    viewModel.trimEnd = max(newValue, viewModel.trimStart + 0.1)
                                    viewModel.seek(to: viewModel.trimEnd)
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                    viewModel.resumeAfterScrubbing()
                                }
                        )
                        .zIndex(1) // Ensure handles are above the draggable region
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func startPosition(in width: CGFloat) -> CGFloat {
        guard viewModel.videoDuration > 0 else { return 0 }
        return (viewModel.trimStart / viewModel.videoDuration) * width
    }
    
    private func selectedWidth(in width: CGFloat) -> CGFloat {
        guard viewModel.videoDuration > 0 else { return width }
        return ((viewModel.trimEnd - viewModel.trimStart) / viewModel.videoDuration) * width
    }
    
    private func endPosition(in width: CGFloat) -> CGFloat {
        guard viewModel.videoDuration > 0 else { return 0 }
        return ((viewModel.videoDuration - viewModel.trimEnd) / viewModel.videoDuration) * width
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}

struct TrimHandle: View {
    let isStart: Bool
    let isDragging: Bool
    
    var body: some View {
        ZStack {
            // Handle background with gradient
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 44)
                .shadow(color: Theme.accent.opacity(isDragging ? 0.6 : 0.3), radius: isDragging ? 8 : 4, x: 0, y: 2)
            
            // Grip lines
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 6, height: 2)
                }
            }
        }
        .scaleEffect(isDragging ? 1.15 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
    }
}

struct ExportingView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var gifConverter: GifConverter
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Creating GIF")
                    .font(.title)
                    .foregroundColor(Theme.text)
                Text("This might take a moment...")
                    .foregroundColor(Theme.textSecondary)
            }
            
            ProgressView(value: gifConverter.progress)
                .progressViewStyle(.linear)
                .frame(width: 300)
                .accentColor(Theme.accent)
            
            if let error = gifConverter.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                Button("Try Again") {
                    viewModel.state = .editing
                }
                .padding()
            }
        }
    }
}

extension View {
    func pulseEffect() -> some View {
        self.modifier(PulseModifier())
    }
}

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.5 : 1.0)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
