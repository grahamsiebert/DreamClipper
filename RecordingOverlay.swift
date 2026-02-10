import SwiftUI
import AppKit

// MARK: - Toolbar Phase

enum ToolbarPhase: Equatable {
    case ready               // "Select Window" button (initial state)
    case picking             // "Click a window to select it" + Cancel
    case confirmWindow       // App icon + name + Cancel / Resize & Record
    case resizing            // Spinner + "Resizing window…"
    case recording           // Pause / Stop / Discard
}

// MARK: - Overlay Views

class OverlayView: NSView {
    var holeRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fill entire view with semi-transparent black (darker for Screen Studio look)
        let backgroundColor = NSColor.black.withAlphaComponent(0.65)
        backgroundColor.setFill()
        dirtyRect.fill()

        // Clear the hole area with rounded corners
        if holeRect != .zero {
            let cornerRadius: CGFloat = 16.0
            let holePath = NSBezierPath(roundedRect: holeRect, xRadius: cornerRadius, yRadius: cornerRadius)

            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            holePath.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            // Draw a subtle glow/border around the hole
            let glowRect = holeRect.insetBy(dx: -1, dy: -1)
            let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: cornerRadius + 1, yRadius: cornerRadius + 1)
            NSColor.white.withAlphaComponent(0.08).setStroke()
            glowPath.lineWidth = 2.0
            glowPath.stroke()
        }
    }
}

/// Secondary overlay window for additional screens (no recording hole)
class SecondaryOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        let overlayView = OverlayView()
        overlayView.holeRect = .zero // No hole on secondary screens
        self.contentView = overlayView
    }
}

class RecordingOverlayWindow: NSWindow {
    let overlayView = OverlayView()
    private var overlayWindows: [SecondaryOverlayWindow] = []

    init(holeRect: CGRect, targetScreen: NSScreen) {
        // Initialize with the target screen's frame
        super.init(
            contentRect: targetScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false // Fix crash

        self.contentView = overlayView
        // holeRect is already in Cocoa view coordinates (converted by AppViewModel)
        self.overlayView.holeRect = holeRect

        // Create overlay windows for all other screens (no holes)
        for screen in NSScreen.screens where screen != targetScreen {
            let additionalOverlay = SecondaryOverlayWindow(screen: screen)
            overlayWindows.append(additionalOverlay)
        }
    }

    func orderFrontAll() {
        self.orderFront(nil)
        for window in overlayWindows {
            window.orderFront(nil)
        }
    }

    func closeAll() {
        // First hide all windows immediately with orderOut
        for window in overlayWindows {
            window.orderOut(nil)
        }
        self.orderOut(nil)

        // Then close them properly
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        self.close()
    }

    func updateHole(rect: CGRect) {
        overlayView.holeRect = rect
    }
}

// MARK: - Unified Floating Toolbar Window

class FloatingToolbarWindow: NSWindow {
    init() {
        // Use full screen width so SwiftUI content auto-centers
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: screenWidth, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.level = .floating + 3 // Above picker overlay
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
    }

    /// Position the window at bottom-center of the main screen
    func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let x = screenFrame.origin.x
        let y = screen.visibleFrame.minY + 50
        self.setFrame(NSRect(x: x, y: y, width: screenFrame.width, height: 70), display: true)
    }
}

// MARK: - Unified Floating Toolbar View

struct FloatingToolbarView: View {
    @ObservedObject var viewModel: AppViewModel

    // Hover states for buttons
    @State private var isHoveringSelect = false
    @State private var isHoveringCancel = false
    @State private var isHoveringRecord = false
    @State private var isHoveringStop = false
    @State private var isHoveringPause = false
    @State private var isHoveringDiscard = false
    @State private var isHoveringHelp = false
    // Pulsing animation
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 14) {
            switch viewModel.toolbarPhase {
            case .ready:
                readyContent

            case .picking:
                pickingContent

            case .confirmWindow:
                confirmWindowContent

            case .resizing:
                resizingContent

            case .recording:
                recordingContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Theme.surface)
                .overlay(
                    Capsule()
                        .stroke(Theme.borderLight, lineWidth: 1)
                )
        )
        .fixedSize()
        .frame(maxWidth: .infinity) // Center within the full-width window
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.toolbarPhase)
    }

    // MARK: - Phase: Ready (Select Window)

    private var readyContent: some View {
        Group {
            // Close Button (Quit App)
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(isHoveringCancel ? Theme.surfaceHover : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringCancel = hovering
                }
            }
            .help("Quit DreamClipper")
            
            Button(action: {
                viewModel.startPicking()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 14))
                    Text("Select Window")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Theme.accentGradient)
                .clipShape(Capsule())
                .scaleEffect(isHoveringSelect ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringSelect)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringSelect = $0 }
            
            // Help Button
            helpButton
        }
    }

    // MARK: - Phase: Picking

    private var pickingContent: some View {
        Group {
            // Cancel button on the left
            cancelButton

            Spacer()

            Text("Click a window to select it")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .fixedSize()

            Spacer()

            // Help Button
            helpButton
        }
    }

    // MARK: - Phase: Confirm Window

    private var confirmWindowContent: some View {
        Group {
            if let window = viewModel.selectedWindow {
                // App icon
                if let icon = appIcon(for: window) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                        .foregroundColor(Theme.textSecondary)
                }

                // Window info
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)

                    Text("\(window.name)  •  \(Int(window.frame.width))×\(Int(window.frame.height))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 200)
            }

            Spacer().frame(width: 4)

            cancelButton

            // Resize & Record button
            Button(action: {
                viewModel.startRecordingFromPicker(resize: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 13))
                    Text("Resize & Record")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.accentGradient)
                .clipShape(Capsule())
                .scaleEffect(isHoveringRecord ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringRecord)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRecord = $0 }
        }
    }

    // MARK: - Phase: Resizing

    private var resizingContent: some View {
        Group {
            // Small spinning indicator
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 28, height: 28)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 20, height: 20)
                    .scaleEffect(isPulsing ? 1.0 : 0.7)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }
            }

            if let message = viewModel.resizeFailureMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } else {
                Text("Resizing window to 16:9")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    // MARK: - Phase: Recording

    private var recordingContent: some View {
        Group {
            // Pause/Resume Button
            Button(action: {
                if viewModel.screenRecorder.isPaused {
                    viewModel.resumeRecording()
                } else {
                    viewModel.pauseRecording()
                }
            }) {
                Image(systemName: viewModel.screenRecorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(isHoveringPause ? Theme.surfaceHover : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringPause = hovering
                }
            }
            .help(viewModel.screenRecorder.isPaused ? "Resume Recording" : "Pause Recording")

            // Stop Button (primary action)
            Button(action: {
                viewModel.stopRecording()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isHoveringStop ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHoveringStop)
            .onHover { hovering in
                isHoveringStop = hovering
            }
            .help("Stop Recording")

            // Discard Button
            Button(action: {
                viewModel.discardRecording()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(isHoveringDiscard ? Theme.surfaceHover : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringDiscard = hovering
                }
            }
            .help("Discard Recording")
        }
    }

    // MARK: - Shared Components

    private var helpButton: some View {
        Button(action: {
            viewModel.showHelp(context: .selection)
        }) {
            Image(systemName: "questionmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isHoveringHelp ? Theme.surfaceHover : Theme.surface)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringHelp = hovering
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.updateManager?.updateAvailable == true {
                Circle()
                    .fill(Color(hex: "FF9500"))
                    .frame(width: 10, height: 10)
                    .offset(x: 1, y: 1)
            }
        }
        .help(viewModel.updateManager?.updateAvailable == true ? "Update available" : "Help")
    }

    private var cancelButton: some View {
        Button(action: {
            viewModel.cancelPicker()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isHoveringCancel ? Theme.surfaceHover : Theme.surface)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringCancel = hovering
            }
        }
        .help("Cancel")
    }

    // MARK: - Helpers

    private func appIcon(for window: WindowInfo) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid_t(window.ownerPid)) {
            return app.icon
        }
        return nil
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Window Picker Overlay

/// NSView that tracks mouse movement, highlights windows under the cursor, and handles clicks.
class WindowPickerOverlayNSView: NSView {
    var onMouseMoved: ((NSPoint) -> CGRect?)?
    var onMouseClicked: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var highlightRect: CGRect = .zero
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if let rect = onMouseMoved?(locationInView) {
            highlightRect = rect
        } else {
            highlightRect = .zero
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseClicked?()
    }

    override func mouseExited(with event: NSEvent) {
        highlightRect = .zero
        needsDisplay = true
        onMouseExited?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Removed semi-transparent dark scrim as requested
        // NSColor.black.withAlphaComponent(0.25).setFill()
        // dirtyRect.fill()

        guard highlightRect != .zero else { return }

        // Purple highlight border around hovered window
        let borderInset: CGFloat = -3
        let highlightBorder = highlightRect.insetBy(dx: borderInset, dy: borderInset)
        let borderPath = NSBezierPath(roundedRect: highlightBorder, xRadius: 8, yRadius: 8)

        // Semi-transparent fill
        NSColor(Theme.accent).withAlphaComponent(0.08).setFill()
        borderPath.fill()

        // Border stroke
        NSColor(Theme.accent).withAlphaComponent(0.8).setStroke()
        borderPath.lineWidth = 3.0
        borderPath.stroke()
    }
}

/// Full-screen borderless transparent window that captures mouse events for the picker.
class WindowPickerOverlayWindow: NSWindow {
    let pickerView = WindowPickerOverlayNSView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating + 2
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.contentView = pickerView
    }
}
