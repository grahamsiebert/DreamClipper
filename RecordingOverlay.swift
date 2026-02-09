import SwiftUI
import AppKit

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

class ResizingModalWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 250),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false // We'll use SwiftUI shadow instead
        self.level = .modalPanel
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = self.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

class RecordingToolbarWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 90),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating + 1
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.center()
        self.isReleasedWhenClosed = false
    }
}

struct RecordingToolbarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHoveringStop = false
    @State private var isHoveringPause = false
    @State private var isHoveringDiscard = false

    var body: some View {
        HStack(spacing: 14) {
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
    }
}

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

struct ResizingModalView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 28) {
            // Pulsing circle indicator
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.2), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 52, height: 52)
                    .pulseEffect()
            }

            // Text content
            VStack(spacing: 10) {
                Text("Resizing Window")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)

                if let message = viewModel.resizeFailureMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else {
                    Text("Adjusting to 16:9 aspect ratio...")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(44)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusXL)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusXL)
                        .stroke(Theme.borderLight, lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
