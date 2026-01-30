import SwiftUI
import AVKit

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // Hide all controls - we use our custom timeline for trimming
        view.controlsStyle = .none
        view.showsFrameSteppingButtons = false
        view.showsSharingServiceButton = false
        view.showsFullScreenToggleButton = false
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }
}
