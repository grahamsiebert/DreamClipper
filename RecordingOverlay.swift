import SwiftUI
import AppKit

class OverlayView: NSView {
    var holeRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Fill entire view with semi-transparent black
        let backgroundColor = NSColor.black.withAlphaComponent(0.5)
        backgroundColor.setFill()
        dirtyRect.fill()
        
        // Clear the hole area with rounded corners
        if holeRect != .zero {
            let cornerRadius: CGFloat = 12.0
            let holePath = NSBezierPath(roundedRect: holeRect, xRadius: cornerRadius, yRadius: cornerRadius)
            
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            holePath.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            
            // Draw a subtle border around the hole
            NSColor.white.withAlphaComponent(0.2).setStroke()
            holePath.lineWidth = 1.0
            holePath.stroke()
        }
    }
}

class RecordingOverlayWindow: NSWindow {
    let overlayView = OverlayView()
    private var overlayWindows: [NSWindow] = []

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
            let additionalOverlay = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            additionalOverlay.backgroundColor = .clear
            additionalOverlay.isOpaque = false
            additionalOverlay.hasShadow = false
            additionalOverlay.level = .floating
            additionalOverlay.ignoresMouseEvents = true
            additionalOverlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            additionalOverlay.isReleasedWhenClosed = false

            let additionalOverlayView = OverlayView()
            additionalOverlayView.holeRect = .zero // No hole on other screens
            additionalOverlay.contentView = additionalOverlayView

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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .modalPanel
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.center()
        self.isReleasedWhenClosed = false
    }
}

class RecordingToolbarWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 70),
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
        self.isReleasedWhenClosed = false // Fix crash
    }
}

struct RecordingToolbarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHoveringStop = false
    @State private var isHoveringPause = false
    @State private var isHoveringDiscard = false
    
    // Theme colors are handled via Theme.swift now
    
    var body: some View {
        HStack(spacing: 12) {
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
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isHoveringPause ? Theme.surfaceHover : Theme.surface)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
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
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isHoveringStop ? 1.03 : 1.0)
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
                    .foregroundColor(.gray)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isHoveringDiscard ? Theme.surfaceHover : Theme.surface)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
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
        .padding(8)
        .background(
            Capsule()
                .fill(Theme.background)
                .overlay(
                    Capsule()
                        .stroke(Theme.border, lineWidth: 1)
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
        VStack(spacing: 24) {
            // Pulsing circle indicator
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 48, height: 48)
                    .pulseEffect()
            }

            // Text content
            VStack(spacing: 8) {
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
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
    }
}
