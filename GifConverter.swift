import Foundation
import AVFoundation
import ImageIO
import AppKit
import UniformTypeIdentifiers

enum GifResolution: String, CaseIterable {
    case fullHD = "1080p"
    case hd = "720p"
    
    var size: (width: Int, height: Int) {
        switch self {
        case .fullHD: return (1920, 1080)
        case .hd: return (1280, 720)
        }
    }
}

struct GifConfig {
    let sourceURL: URL
    let startTime: Double
    let endTime: Double
    let frameRate: Int
    let resolution: GifResolution
    let sampleFactor: Int // 1 = full encode, 3 = estimate (encode 1/3 frames)
    
    init(sourceURL: URL, startTime: Double, endTime: Double, frameRate: Int, resolution: GifResolution = .fullHD, sampleFactor: Int = 1) {
        self.sourceURL = sourceURL
        self.startTime = startTime
        self.endTime = endTime
        self.frameRate = frameRate
        self.resolution = resolution
        self.sampleFactor = sampleFactor
    }
}

enum GifOutput {
    case file(URL)
    case memory(NSMutableData)
}

struct GifResult {
    let byteCount: Int
    let data: Data?
}

class GifConverter: ObservableObject {
    @Published var isConverting = false
    @Published var progress: Double = 0.0
    @Published var error: String?
    
    // Generic entry point
    func convert(config: GifConfig, output: GifOutput) async throws -> GifResult {
        await MainActor.run {
            self.isConverting = true
            self.progress = 0.0
            self.error = nil
        }
        
        defer {
            Task { @MainActor in
                self.isConverting = false
            }
        }
        
        return try await Task.detached(priority: .userInitiated) {
            do {
                return try await self.generateGif(config: config, output: output)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
                throw error
            }
        }.value
    }
    
    private func generateGif(config: GifConfig, output: GifOutput) async throws -> GifResult {
        let asset = AVURLAsset(url: config.sourceURL)
        let reader = try AVAssetReader(asset: asset)
        
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let duration = try await asset.load(.duration).seconds
        
        // Validate and clamp times
        let start = max(0, config.startTime)
        let end = min(duration, config.endTime)
        guard end > start else { throw NSError(domain: "GifConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid time range"]) }
        
        // Setup Reader with TimeRange
        let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                  duration: CMTime(seconds: end - start, preferredTimescale: 600))
        reader.timeRange = timeRange
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: config.resolution.size.width,
            kCVPixelBufferHeightKey as String: config.resolution.size.height
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(readerOutput)
        reader.startReading()
        
        // Setup Destination
        let destination: CGImageDestination
        let outputData: NSMutableData?
        
        switch output {
        case .file(let url):
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
                 throw NSError(domain: "GifConverter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create file destination"])
            }
            destination = dest
            outputData = nil
        case .memory(let data):
            guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 0, nil) else {
                 throw NSError(domain: "GifConverter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create data destination"])
            }
            destination = dest
            outputData = data
        }
        
        // Global Properties
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        // Frame Properties
        let delayTime = 1.0 / Double(config.frameRate)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delayTime,
                kCGImagePropertyGIFUnclampedDelayTime: delayTime
            ]
        ]
        
        // Scheduling Logic
        let totalDuration = end - start
        let expectedFrameCount = Int(ceil(totalDuration * Double(config.frameRate)))
        
        var currentFrameIndex = 0
        var latestCGImage: CGImage?
        var sampleBuffer: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
        let context = CIContext()
        
        // Sampling Counter
        // If sampleFactor is 3, we process index 0, 3, 6...
        // We still iterate through all indices to maintain timing logic, but simply skip 'AddImage' for skipped frames
        // AND we must ensure we don't do expensive decoding for ignored frames if possible.
        // However, the reader loop logic (catching up to timestamp) is needed.
        
        // Optimization: For sampling, we actually want to SKIP the encoding step.
        // We still need to find the frame content.
        
        // Actually, if we skip frames in GIF, the duration is messed up unless we adjust delay.
        // But we want to simulate the FULL GIF size.
        // If we encode 1/3 frames, the resulting file is 1/3 the size.
        // So we will just multiple the final byte count by sampleFactor.
        
        while currentFrameIndex < expectedFrameCount {
            let targetTimeRelativeToStart = Double(currentFrameIndex) * delayTime
            let targetAbsoluteTime = start + targetTimeRelativeToStart
            
            // Reader Sync Logic
            var confirmedSample: CMSampleBuffer? = nil
            while let sb = sampleBuffer {
                let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                if t <= targetAbsoluteTime + 0.005 {
                    confirmedSample = sb
                    sampleBuffer = readerOutput.copyNextSampleBuffer()
                } else {
                    break
                }
            }
            
            if let sb = confirmedSample {
                // Decode only if we are going to use this frame (or if it's the first one, to have a base)
                let shouldProcess = (currentFrameIndex % config.sampleFactor == 0)
                
                if shouldProcess {
                    if let imageBuffer = CMSampleBufferGetImageBuffer(sb) {
                        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                            latestCGImage = cgImage
                        }
                    }
                }
            }
            
            // Write frame only if sampled
            if currentFrameIndex % config.sampleFactor == 0 {
                if let image = latestCGImage {
                    CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
                }
            }
            
            currentFrameIndex += 1
            
            if currentFrameIndex % 5 == 0 {
                // If sampling, effective progress is faster
                let p = Double(currentFrameIndex) / Double(expectedFrameCount)
                await MainActor.run { self.progress = p }
            }
        }
        
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "GifConverter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"])
        }
        
        let byteCount: Int
        if let data = outputData {
            byteCount = data.count
        } else if case .file(let url) = output {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            byteCount = resources.fileSize ?? 0
        } else {
            byteCount = 0
        }
        
        return GifResult(byteCount: byteCount, data: outputData as Data?)
    }
}
