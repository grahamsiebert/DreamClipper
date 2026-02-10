import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            if !viewModel.windowManager.hasAccessibilityPermission || !viewModel.windowManager.hasScreenRecordingPermission {
                OnboardingView(windowManager: viewModel.windowManager, viewModel: viewModel)
            } else {
                VStack {
                    switch viewModel.state {
                    case .selection, .picking, .confirming, .resizing:
                        // Main window is hidden during selection/recording phases
                        // The floating toolbar is the primary UI here
                        Color.clear
                            .onAppear {
                                viewModel.showFloatingToolbar()
                                // Delay hide to ensure window is fully initialized
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewModel.hideMainWindow()
                                }
                            }
                    case .recording:
                        RecordingView(viewModel: viewModel, screenRecorder: viewModel.screenRecorder)
                            .padding()
                    case .editing:
                        EditingView(viewModel: viewModel)
                            .padding()
                    case .exporting:
                        ExportingView(viewModel: viewModel, gifConverter: viewModel.gifConverter)
                            .padding()
                    case .done(let exportedURL):
                        DoneView(viewModel: viewModel, exportedURL: exportedURL)
                            .padding()
                    case .help(let context, _):
                        HelpView(context: context, viewModel: viewModel)
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(.dark)
    }
}

struct OnboardingView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var viewModel: AppViewModel
    @State private var currentStep = 0
    @State private var permissionTimer: Timer?

    var body: some View {
        VStack(spacing: 40) {
            // Header with Help Button
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.showHelp(context: .onboarding)
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show Help")
                }
                .padding(.horizontal)

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
                    // Just open System Settings - no need for the system prompt dialog
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
                    // Trigger permission request to add app to the Screen Recording list
                    windowManager.requestScreenRecordingPermission()
                    // Also open System Settings so user can toggle the permission
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(36)
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadiusXL)
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
                        .padding(.vertical, 14)
                        .background(Theme.accentGradient)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.cornerRadiusMedium)
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
                    .fill(isCompleted ? Color.green : (isActive ? Theme.accent : Theme.surfaceSecondary))
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
                        .padding(.vertical, 10)
                        .background(isActive ? Theme.accent.opacity(0.15) : Theme.surfaceSecondary)
                        .foregroundColor(isActive ? Theme.accent : Theme.textSecondary)
                        .cornerRadius(Theme.cornerRadiusSmall)
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
        .opacity(isActive || isCompleted ? 1.0 : 0.5)
    }
}




struct RecordingView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var screenRecorder: ScreenRecorder

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .pulseEffect()
            }

            VStack(spacing: 10) {
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
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
                .fontWeight(.bold)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(Theme.cornerRadiusMedium)
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
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Recording")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()

                // Help Button
                Button(action: {
                    viewModel.showHelp(context: .editing)
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Show Help")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Video Preview & Timeline Card
            VStack(spacing: 0) {
                // Video Player
                GeometryReader { geometry in
                    ZStack {
                        Theme.surfaceSecondary

                        if let player = viewModel.player {
                            PlayerView(player: player)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Theme.cornerRadiusXL,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: Theme.cornerRadiusXL
                    )
                )
                .clipped()

                // Timeline
                TimelineView(viewModel: viewModel)
                    .frame(height: 80)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(Theme.surface)
            }
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadiusXL)
            .padding(.horizontal, 24)
            
            // Controls & Actions Bar
            HStack(spacing: 24) {
                // Settings Group using Grid for perfect alignment
                Grid(horizontalSpacing: 24, verticalSpacing: 0) {
                    GridRow {
                        // Framerate Column
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Framerate")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .textCase(.uppercase)
                                .fixedSize()

                            HStack(spacing: 8) {
                                ForEach([15, 30, 60], id: \.self) { rate in
                                    Button(action: {
                                        viewModel.targetFramerate = rate
                                    }) {
                                        Text("\(rate)")
                                            .font(.system(size: 12, weight: viewModel.targetFramerate == rate ? .semibold : .medium))
                                            .foregroundColor(viewModel.targetFramerate == rate ? Theme.text : Theme.textSecondary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(viewModel.targetFramerate == rate ? Color.white.opacity(0.15) : Color.clear)
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(Theme.borderLight, lineWidth: viewModel.targetFramerate == rate ? 1 : 0.5)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Resolution Column
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resolution")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .textCase(.uppercase)
                                .fixedSize()

                            HStack(spacing: 8) {
                                Button(action: {
                                    viewModel.resolution = .fullHD
                                }) {
                                    Text("1080p")
                                        .font(.system(size: 12, weight: viewModel.resolution == .fullHD ? .semibold : .medium))
                                        .foregroundColor(viewModel.resolution == .fullHD ? Theme.text : Theme.textSecondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(viewModel.resolution == .fullHD ? Color.white.opacity(0.15) : Color.clear)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Theme.borderLight, lineWidth: viewModel.resolution == .fullHD ? 1 : 0.5)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    viewModel.resolution = .hd
                                }) {
                                    Text("720p")
                                        .font(.system(size: 12, weight: viewModel.resolution == .hd ? .semibold : .medium))
                                        .foregroundColor(viewModel.resolution == .hd ? Theme.text : Theme.textSecondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(viewModel.resolution == .hd ? Color.white.opacity(0.15) : Color.clear)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Theme.borderLight, lineWidth: viewModel.resolution == .hd ? 1 : 0.5)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()

                // Estimated Size with Warning Tooltip
                HStack(spacing: 16) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1, height: 36)

                    EstimatedSizeView(viewModel: viewModel)

                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1, height: 36)
                }
                .overlay(alignment: .bottom) {
                    // Warning tooltip floats below the size indicator, outside the layout flow
                    if viewModel.showSizeWarning {
                        SizeWarningTooltip(isShowing: $viewModel.showSizeWarning)
                            .fixedSize()
                            .offset(y: 52)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.showSizeWarning)

                Spacer()

                // Action Buttons
                HStack(spacing: 14) {
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(isHoveringDiscard ? Theme.surfaceHover : Theme.surfaceSecondary)
                        )
                        .contentShape(Capsule())
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
                                .fixedSize() // Ensure text stays on one line
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                        .scaleEffect(isHoveringExport ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringExport)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringExport = $0 }
                }
            }
            .padding(24)
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadiusXL)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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

    private let handleWidth: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let trackInset: CGFloat = handleWidth // Inset track so handles don't get clipped
            let trackWidth = totalWidth - (trackInset * 2)

            VStack(spacing: 10) {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceSecondary)
                    .cornerRadius(Theme.cornerRadiusSmall)

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
                .padding(.horizontal, trackInset)

                // Timeline track with handles
                ZStack(alignment: .leading) {
                    // Track background - inset to leave room for handles
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(Theme.surfaceSecondary)
                        .frame(height: 36)
                        .padding(.horizontal, trackInset)

                    // Track content (dimmed regions + selected region)
                    HStack(spacing: 0) {
                        // Before start (dimmed)
                        if startPosition(in: trackWidth) > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: startPosition(in: trackWidth))
                        }

                        // Selected region
                        Rectangle()
                            .fill(Theme.accent.opacity(isDraggingRange ? 0.2 : 0.12))
                            .frame(width: max(1, selectedWidth(in: trackWidth)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Theme.accent.opacity(0.8), lineWidth: isDraggingRange ? 2 : 1.5)
                            )
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isDraggingRange {
                                            isDraggingRange = true
                                            dragStartOffset = value.startLocation.x
                                            viewModel.pauseForScrubbing()
                                        }

                                        let duration = viewModel.trimEnd - viewModel.trimStart
                                        let dragDelta = value.location.x - dragStartOffset
                                        let currentStartPos = startPosition(in: trackWidth)
                                        let newStartPos = currentStartPos + dragDelta

                                        let newStartPercentage = newStartPos / trackWidth
                                        var newStart = viewModel.videoDuration * newStartPercentage

                                        newStart = max(0, min(viewModel.videoDuration - duration, newStart))
                                        let newEnd = newStart + duration

                                        viewModel.trimStart = newStart
                                        viewModel.trimEnd = newEnd
                                        viewModel.seek(to: newStart)

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
                                .fill(Color.black.opacity(0.6))
                                .frame(width: endPosition(in: trackWidth))
                        }
                    }
                    .frame(height: 36)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .padding(.horizontal, trackInset)

                    // Start handle - positioned from left edge
                    TrimHandle(isStart: true, isDragging: isDraggingStart)
                        .position(
                            x: trackInset + startPosition(in: trackWidth),
                            y: 22
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingStart {
                                        isDraggingStart = true
                                        viewModel.pauseForScrubbing()
                                    }
                                    let x = value.location.x - trackInset
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
                        .zIndex(1)

                    // End handle
                    TrimHandle(isStart: false, isDragging: isDraggingEnd)
                        .position(
                            x: trackInset + startPosition(in: trackWidth) + selectedWidth(in: trackWidth),
                            y: 22
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingEnd {
                                        isDraggingEnd = true
                                        viewModel.pauseForScrubbing()
                                    }
                                    let x = value.location.x - trackInset
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
                        .zIndex(1)
                }
                .frame(height: 44) // Fixed height for the track area
            }
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
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 44)
                .shadow(color: Theme.accent.opacity(isDragging ? 0.5 : 0.25), radius: isDragging ? 10 : 6, x: 0, y: 2)

            // Grip lines
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 6, height: 2)
                }
            }
        }
        .scaleEffect(isDragging ? 1.12 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
    }
}

struct ExportingView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var gifConverter: GifConverter

    var body: some View {
        VStack(spacing: 40) {
            // Circular Progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Theme.surfaceSecondary, lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Progress circle
                Circle()
                    .trim(from: 0, to: gifConverter.progress)
                    .stroke(
                        Theme.accentGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: gifConverter.progress)

                // Percentage text
                VStack(spacing: 2) {
                    Text("\(Int(gifConverter.progress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                }
            }

            VStack(spacing: 12) {
                Text("Creating GIF")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.text)

                Text(progressStatusText)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
            }

            if let error = gifConverter.error {
                VStack(spacing: 16) {
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
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Theme.surfaceHover)
                .foregroundColor(Theme.text)
                .cornerRadius(Theme.cornerRadiusSmall)
            }
        }
        .padding(56)
        .background(Theme.surface)
        .cornerRadius(Theme.cornerRadiusXL)
    }

    private var progressStatusText: String {
        let progress = gifConverter.progress
        if progress < 0.85 {
            return "Extracting frames..."
        } else if progress < 0.95 {
            return "Encoding GIF..."
        } else {
            return "Finalizing..."
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

// MARK: - Done View

struct DoneView: View {
    @ObservedObject var viewModel: AppViewModel
    let exportedURL: URL
    @State private var isHoveringFolder = false
    @State private var isHoveringNew = false
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.3
    @State private var confettiOpacity: Double = 0

    var body: some View {
        VStack(spacing: 36) {
            // Success Animation
            ZStack {
                // Confetti circles
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(confettiColor(for: index))
                        .frame(width: 12, height: 12)
                        .offset(confettiOffset(for: index))
                        .opacity(confettiOpacity)
                        .scaleEffect(confettiOpacity)
                }

                // Outer ring
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 6)
                    .frame(width: 120, height: 120)

                // Inner filled circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.green.opacity(0.4), radius: 20, x: 0, y: 8)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(showCheckmark ? 1 : 0)
            }

            // Text
            VStack(spacing: 12) {
                Text("GIF Created!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("Your GIF has been saved successfully")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)

                // File name
                Text(exportedURL.lastPathComponent)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.1))
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .padding(.top, 4)
            }

            // Action Buttons
            HStack(spacing: 16) {
                // Show in Folder
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 15))
                        Text("Show in Folder")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(isHoveringFolder ? Theme.text : Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(isHoveringFolder ? Theme.surfaceHover : Theme.surfaceSecondary)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringFolder = $0 }

                // Create New GIF
                Button(action: {
                    viewModel.reset()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                        Text("Create New GIF")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Theme.accentGradient)
                    .clipShape(Capsule())
                    .scaleEffect(isHoveringNew ? 1.03 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringNew)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringNew = $0 }
            }
        }
        .padding(56)
        .background(Theme.surface)
        .cornerRadius(Theme.cornerRadiusXL)
        .onAppear {
            // Animate checkmark
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                showCheckmark = true
                checkmarkScale = 1.0
            }

            // Animate confetti
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                confettiOpacity = 1.0
            }

            // Fade out confetti
            withAnimation(.easeIn(duration: 0.8).delay(1.5)) {
                confettiOpacity = 0
            }
        }
    }

    private func confettiColor(for index: Int) -> Color {
        let colors: [Color] = [
            Theme.accent,
            .green,
            .orange,
            .pink,
            Theme.accent.opacity(0.7),
            .green.opacity(0.7),
            .yellow,
            .purple
        ]
        return colors[index % colors.count]
    }

    private func confettiOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / 8.0) * .pi / 180.0
        let radius: CGFloat = 80
        return CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius
        )
    }
}

// MARK: - Help System

enum HelpContext {
    case onboarding
    case selection
    case editing
}
struct HelpView: View {
    let context: HelpContext
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject var updateManager: UpdateManager
    @State private var selectedTab: HelpTab = .contextHelp

    enum HelpTab {
        case contextHelp
        case faq
        case about
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(spacing: 0) {
                // Back Button and Title Row
                HStack {
                    // Back Button
                    Button(action: {
                        viewModel.closeHelp()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent.opacity(0.12))
                        .cornerRadius(Theme.cornerRadiusSmall)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.accent)

                        Text("Help & Support")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }

                    Spacer()

                    // Update Available button or invisible placeholder for balance
                    if updateManager.updateAvailable {
                        Button(action: {
                            updateManager.checkForUpdates()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 13))
                                if let version = updateManager.updateVersion {
                                    Text("Update v\(version)")
                                        .font(.system(size: 12, weight: .semibold))
                                } else {
                                    Text("Update Available")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .foregroundColor(Color(hex: "FF9500"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "FF9500").opacity(0.12))
                            .cornerRadius(Theme.cornerRadiusSmall)
                        }
                        .buttonStyle(.plain)
                        .help("Click to update DreamClipper")
                    } else {
                        Color.clear.frame(width: 90)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                // Tab Navigation
                HStack(spacing: 8) {
                    HelpTabButton(title: "Guide", icon: "book.fill", isSelected: selectedTab == .contextHelp) {
                        selectedTab = .contextHelp
                    }
                    HelpTabButton(title: "FAQ", icon: "questionmark.circle", isSelected: selectedTab == .faq) {
                        selectedTab = .faq
                    }
                    HelpTabButton(title: "About", icon: "info.circle", isSelected: selectedTab == .about) {
                        selectedTab = .about
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(Theme.surface)
            .fixedSize(horizontal: false, vertical: true)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    switch selectedTab {
                    case .contextHelp:
                        ContextHelpContent(context: context)
                    case .faq:
                        FAQContent()
                    case .about:
                        AboutContent()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct HelpTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
            .cornerRadius(Theme.cornerRadiusSmall)
        }
        .buttonStyle(.plain)
    }
}

struct ContextHelpContent: View {
    let context: HelpContext

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch context {
            case .onboarding:
                OnboardingHelp()
            case .selection:
                SelectionHelp()
            case .editing:
                EditingHelp()
            }
        }
    }
}

struct OnboardingHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HelpSection(title: "Getting Started", icon: "hand.wave.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DreamClipper needs two permissions to function:")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)

                    HelpBullet(title: "Accessibility Permission", description: "Allows DreamClipper to resize and position windows to the optimal 1920x1080 recording size.")

                    HelpBullet(title: "Screen Recording Permission", description: "Allows DreamClipper to capture the window content for recording.")
                }
            }

            HelpSection(title: "Granting Permissions", icon: "lock.open.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    HelpStep(number: 1, text: "Click 'Open Settings' if prompted for permissions")
                    HelpStep(number: 2, text: "In System Settings, enable DreamClipper in the Accessibility list")
                    HelpStep(number: 3, text: "Return to DreamClipper (permission will be detected automatically)")
                    HelpStep(number: 4, text: "Repeat for Screen Recording Permission")
                    HelpStep(number: 5, text: "The app is ready when you see the 'Select Window' toolbar")
                }
            }

            HelpSection(title: "Troubleshooting", icon: "wrench.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Permission not detected?", description: "Try quitting and restarting DreamClipper after granting permissions.")
                    HelpBullet(title: "Can't find DreamClipper in Settings?", description: "Click 'Open Settings' again - this will trigger macOS to add the app to the list.")
                    HelpBullet(title: "Blank Window?", description: "If you see a blank window, try clicking the 'x' on the toolbar to quit and relaunch.")
                }
            }
        }
    }
}

struct SelectionHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HelpSection(title: "Selecting a Window", icon: "macwindow") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Click 'Select Window' on the toolbar to begin. Choose a window from the grid to record. DreamClipper will automatically resize it to 1920x1080 (16:9).")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)

                    HelpBullet(title: "Window Requirements", description: "Windows must be visible, have a title, and be at least 200x200 pixels.")

                    HelpBullet(title: "Refresh", description: "Click the refresh icon if you don't see your window, or if you've opened a new window since launching the app.")
                }
            }

            HelpSection(title: "Recording Process", icon: "record.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    HelpStep(number: 1, text: "Click on a window card to select it")
                    HelpStep(number: 2, text: "Click 'Start Recording'")
                    HelpStep(number: 3, text: "The window will be resized and repositioned (you'll see a brief modal)")
                    HelpStep(number: 4, text: "A grey overlay will cover everything except your selected window")
                    HelpStep(number: 5, text: "Recording controls appear at the bottom of the screen")
                    HelpStep(number: 6, text: "Click the red stop button when finished")
                }
            }

            HelpSection(title: "Tips", icon: "lightbulb.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Multi-Monitor Setup", description: "The overlay will appear on all screens, but only the selected window will be visible.")
                    HelpBullet(title: "Window Can't Resize?", description: "Some apps (like Preview) may restrict window resizing. Recording will proceed with the current window size.")
                    HelpBullet(title: "Best Results", description: "For optimal quality, record windows that can be resized to exactly 1920x1080.")
                }
            }
        }
    }
}

struct EditingHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HelpSection(title: "Editing Your Recording", icon: "film") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("After stopping the recording, you can trim it and adjust the export settings before converting to GIF.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            HelpSection(title: "Trimming", icon: "scissors") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Start/End Handles", description: "Drag the purple handles on the timeline to set the trim start and end points.")
                    HelpBullet(title: "Preview", description: "The video player shows your trimmed selection. Click play to preview.")
                    HelpBullet(title: "Precision", description: "Use the time labels to see exact timestamps for your trim points.")
                }
            }

            HelpSection(title: "Export Settings", icon: "gear") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Frame Rate", description: "Higher frame rates (30-60fps) create smoother animations but larger files. Lower rates (10-20fps) reduce file size.")

                    HelpBullet(title: "Resolution", description: "Choose from Full HD (1920x1080), HD (1280x720), or SD (640x360). Lower resolutions significantly reduce file size.")

                    HelpBullet(title: "File Size Estimate", description: "DreamClipper shows an estimated file size as you adjust settings. This updates in real-time.")
                }
            }

            HelpSection(title: "Exporting", icon: "square.and.arrow.up") {
                VStack(alignment: .leading, spacing: 10) {
                    HelpStep(number: 1, text: "Adjust trim points and export settings")
                    HelpStep(number: 2, text: "Review the estimated file size")
                    HelpStep(number: 3, text: "Click 'Export GIF'")
                    HelpStep(number: 4, text: "Choose a save location and filename")
                    HelpStep(number: 5, text: "Wait for the export to complete (you'll see a progress indicator)")
                }
            }

            HelpSection(title: "Tips for Smaller Files", icon: "doc.badge.arrow.up") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Trim Aggressively", description: "Shorter GIFs = smaller files. Only include what's necessary.")
                    HelpBullet(title: "Lower the Frame Rate", description: "15-20fps is often sufficient for most use cases.")
                    HelpBullet(title: "Reduce Resolution", description: "HD (1280x720) is a good balance between quality and file size.")
                    HelpBullet(title: "Avoid Long Recordings", description: "GIFs work best for 3-10 second clips.")
                }
            }
        }
    }
}

struct FAQContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Frequently Asked Questions")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(.bottom, 8)

            FAQItem(
                question: "Why does DreamClipper need Accessibility permission?",
                answer: "Accessibility permission allows DreamClipper to programmatically resize and position windows. This ensures your recording is always at the optimal 1920x1080 resolution for high-quality output."
            )

            FAQItem(
                question: "My window isn't resizing to 1920x1080. Why?",
                answer: "Some applications restrict window resizing for various reasons (e.g., PDF viewers maintaining aspect ratio, system windows). DreamClipper will record the window at its current size and display a warning. You can still proceed with the recording."
            )

            FAQItem(
                question: "Can I record multiple windows at once?",
                answer: "Currently, DreamClipper records one window at a time. Each recording session focuses on a single window to maintain quality and simplicity."
            )

            FAQItem(
                question: "Why is my GIF file so large?",
                answer: "GIF file size depends on duration, frame rate, and resolution. To reduce size: (1) Trim to only essential frames, (2) Lower the frame rate to 15-20fps, (3) Reduce resolution to HD or SD, (4) Keep recordings under 10 seconds."
            )

            FAQItem(
                question: "What's the maximum recording length?",
                answer: "There's no hard limit, but GIFs are best suited for short clips (3-10 seconds). Longer recordings will result in very large file sizes and may not be practical for sharing."
            )

            FAQItem(
                question: "Can I edit the GIF after exporting?",
                answer: "DreamClipper exports a final GIF file. If you want to make changes, you'll need to start a new recording or use external GIF editing software."
            )

            FAQItem(
                question: "Does DreamClipper record audio?",
                answer: "No, DreamClipper creates GIF files which don't support audio. It only captures visual content from the selected window."
            )

            FAQItem(
                question: "Why is the grey overlay sometimes not aligned with my window?",
                answer: "This can happen if the window moves or resizes after recording starts. DreamClipper captures the window position at the start of recording. Avoid moving or resizing the window during recording."
            )

            FAQItem(
                question: "Can I record on a specific monitor in a multi-monitor setup?",
                answer: "Yes! The grey overlay appears on all screens, but DreamClipper automatically detects which screen contains your selected window and positions the recording hole accordingly."
            )

            FAQItem(
                question: "What happens if I click 'Discard' during recording?",
                answer: "The recording is immediately stopped and deleted. You'll return to the window selection screen. This is useful if you made a mistake and want to start over."
            )

            FAQItem(
                question: "Where are my recordings saved?",
                answer: "Recordings are temporarily stored until you export them. When you click 'Export GIF', you choose the save location. The temporary recording is deleted after successful export."
            )

            FAQItem(
                question: "Can I record system windows or the desktop?",
                answer: "DreamClipper filters out system windows, desktop, and other non-recordable elements. You can only record regular application windows with titles."
            )
        }
    }
}

struct AboutContent: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // App Info
            VStack(alignment: .leading, spacing: 8) {
                Text("DreamClipper")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("Professional Window Recording to GIF")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)

                Text(appVersion)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
            }

            Divider()
                .padding(.vertical, 4)

            // Features
            HelpSection(title: "Features", icon: "star.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HelpBullet(title: "Automatic Window Resizing", description: "Windows are resized to 1920x1080 for optimal quality")
                    HelpBullet(title: "Multi-Monitor Support", description: "Works seamlessly across multiple displays")
                    HelpBullet(title: "Smart Overlay", description: "Grey overlay focuses attention on the recording window")
                    HelpBullet(title: "Trim & Edit", description: "Precise trimming controls and export settings")
                    HelpBullet(title: "Real-time Preview", description: "See your changes before exporting")
                    HelpBullet(title: "File Size Estimation", description: "Know your GIF size before exporting")
                    HelpBullet(title: "Automatic Updates", description: "Get notified when new versions are available")
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Credits
            VStack(alignment: .leading, spacing: 10) {
                Text("Built with")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)

                Text("SwiftUI • AVFoundation • ScreenCaptureKit")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
            }

            Spacer()
        }
    }
}

// MARK: - Helper Components

struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(Theme.accent)
                    .font(.system(size: 18))

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
            }

            content()
                .padding(.leading, 4)
        }
    }
}

struct HelpBullet: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("•")
                .foregroundColor(Theme.accent)
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HelpStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 28, height: 28)

                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.accent)
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Theme.text)
        }
        .padding(.vertical, 2)
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 15))

                    Text(question)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(answer)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shimmer Effect for "Calculating..." text

struct ShimmerText: View {
    let text: String
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundColor(Theme.textSecondary)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Theme.text.opacity(0.6),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: shimmerOffset * geometry.size.width)
                    .mask(
                        Text(text)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    )
                }
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 1.5
                }
            }
    }
}

// MARK: - Size Warning Tooltip

struct SizeWarningTooltip: View {
    @Binding var isShowing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.sizeDanger)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text("File Size Too Large")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)

                Text("The Dreamcatcher Changelog only accepts GIFs under 15MB. Reduce the resolution, framerate, or clip length.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowing = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .padding(4)
                    .background(Circle().fill(Theme.surfaceHover))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .stroke(Theme.sizeDanger.opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .frame(maxWidth: 280)
        .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Estimated Size Display with Color Coding

struct EstimatedSizeView: View {
    @ObservedObject var viewModel: AppViewModel

    private var sizeColor: Color {
        if viewModel.isCalculating {
            return Theme.textSecondary
        }
        let sizeMB = viewModel.estimatedFileSizeMB
        // Show neutral color if size is 0 or invalid
        if sizeMB <= 0 {
            return Theme.textSecondary
        }
        if sizeMB < AppViewModel.sizeWarningThreshold {
            return Theme.sizeGood
        } else if sizeMB < AppViewModel.sizeDangerThreshold {
            return Theme.sizeWarning
        } else {
            return Theme.sizeDanger
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("ESTIMATED SIZE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
                .fixedSize()

            if viewModel.isCalculating {
                ShimmerText(text: "Calculating...")
            } else {
                Text(viewModel.estimatedFileSize)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(sizeColor)
                    .fixedSize()
            }
        }
    }
}
