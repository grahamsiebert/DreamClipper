import Foundation
import ScreenCaptureKit
import AVFoundation
import os

@MainActor
class ScreenRecorder: NSObject, ObservableObject, SCStreamDelegate {
    @Published var isRecording = false
    @Published var recordingURL: URL?
    @Published var error: String?
    @Published var isPaused = false
    
    private let storage = RecorderStorage()
    private var stream: SCStream?
    private let recorderQueue = DispatchQueue(label: "com.dreamclipper.recorder")
    
    func startRecording(window: SCWindow) async {
        if isRecording { return }
        
        do {
            storage.reset()
            isPaused = false
            
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = 1920
            config.height = 1080
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 5
            config.showsCursor = true
            
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: recorderQueue)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            recordingURL = tempURL
            
            try storage.setupWriter(url: tempURL)
            try await newStream.startCapture()
            
            self.stream = newStream
            self.isRecording = true
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func stopRecording() async {
        do {
            try await stream?.stopCapture()
            await storage.finishWriting()
            self.stream = nil
            self.isRecording = false
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        storage.setPaused(true)
    }
    
    func resume() {
        guard isRecording, isPaused else { return }
        isPaused = false
        storage.setPaused(false)
    }
    
    func discard() async {
        try? await stream?.stopCapture()
        storage.cancelWriting()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.isRecording = false
        self.isPaused = false
        self.recordingURL = nil
        self.stream = nil
    }
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.error = error.localizedDescription
            self.isRecording = false
            self.isPaused = false
        }
    }
}

// Wrapper to make non-Sendable types Sendable for transfer across isolation boundaries
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

// Wrapper to make CMSampleBuffer Sendable for the purpose of passing to the serial queue
struct SendableSampleBuffer: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        // CMSampleBuffer is essentially thread-safe for reading, but not marked Sendable.
        // We wrap it to satisfy strict concurrency checking.
        let sendableBuffer = SendableSampleBuffer(buffer: sampleBuffer)
        
        recorderQueue.async { [weak self] in
            // Use the sendable wrapper to pass the buffer into the closure
            self?.storage.processBuffer(sendableBuffer)
        }
    }
}

private final class RecorderStorage: Sendable {
    private struct State: @unchecked Sendable {
        var assetWriter: AVAssetWriter?
        var videoInput: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var isPaused = false
        var offsetTime: CMTime = .zero
        var pauseStartTime: CMTime = .invalid
        var hasStartedSession = false
        var lastSampleTime: CMTime = .invalid
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    func reset() {
        state.withLock { $0 = State() }
    }
    
    func setPaused(_ paused: Bool) {
        state.withLock { state in
            state.isPaused = paused
            if paused {
                state.pauseStartTime = CMClockGetTime(CMClockGetHostTimeClock())
            } else if state.pauseStartTime.isValid {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                let duration = CMTimeSubtract(now, state.pauseStartTime)
                state.offsetTime = CMTimeAdd(state.offsetTime, duration)
                state.pauseStartTime = .invalid // Reset pause start time
            }
        }
    }
    
    func setupWriter(url: URL) throws {
        // We need to create the writer outside the lock to avoid throwing inside withLock if possible,
        // but setup involves updating state.
        // Let's create components first then lock to assign.
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ])
        
        if writer.canAdd(input) {
            writer.add(input)
            
            if !writer.startWriting() {
                throw writer.error ?? NSError(domain: "RecorderStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start writing"])
            }
            
            let wrappedWriter = UncheckedSendable(value: writer)
            let wrappedInput = UncheckedSendable(value: input)
            let wrappedAdaptor = UncheckedSendable(value: adaptor)
            
            state.withLock { state in
                state.assetWriter = wrappedWriter.value
                state.videoInput = wrappedInput.value
                state.adaptor = wrappedAdaptor.value
            }
        } else {
            throw NSError(domain: "RecorderStorage", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input to AVAssetWriter"])
        }
    }
    
    func finishWriting() async {
        let result = state.withLock { state -> (UncheckedSendable<AVAssetWriter?>, UncheckedSendable<AVAssetWriterInput?>) in
            let w = state.assetWriter
            let i = state.videoInput
            // Clear references immediately
            state.assetWriter = nil
            state.videoInput = nil
            state.adaptor = nil
            return (UncheckedSendable(value: w), UncheckedSendable(value: i))
        }
        
        let writer = result.0.value
        let input = result.1.value
        
        guard let writer = writer, writer.status == .writing else { return }
        input?.markAsFinished()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }
    
    func cancelWriting() {
        state.withLock { state in
            state.assetWriter?.cancelWriting()
            state.assetWriter = nil
            state.videoInput = nil
            state.adaptor = nil
        }
    }
    
    func processBuffer(_ sendableBuffer: SendableSampleBuffer) {
        let wrappedBuffer = UncheckedSendable(value: sendableBuffer.buffer)
        state.withLock { state in
            let sampleBuffer = wrappedBuffer.value
            guard !state.isPaused,
                  let writer = state.assetWriter,
                  let input = state.videoInput,
                  let adaptor = state.adaptor,
                  writer.status == .writing,
                  CMSampleBufferIsValid(sampleBuffer) else { return }
            
            var presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentationTime.isValid else { return }
            presentationTime = CMTimeSubtract(presentationTime, state.offsetTime)
            
            if !state.hasStartedSession {
                writer.startSession(atSourceTime: presentationTime)
                state.hasStartedSession = true
                state.lastSampleTime = presentationTime
            }
            
            // Ensure strictly increasing timestamps
            if state.lastSampleTime.isValid && presentationTime <= state.lastSampleTime && state.hasStartedSession {
                // Drop frame if timestamp is not increasing
                return
            }
            
            if input.isReadyForMoreMediaData {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                        state.lastSampleTime = presentationTime
                    } else {
                        // Handle error appending buffer if necessary
                    }
                }
            }
        }
    }
}
