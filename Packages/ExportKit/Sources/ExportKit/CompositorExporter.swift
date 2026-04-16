// Packages/ExportKit/Sources/ExportKit/CompositorExporter.swift

import Foundation
import AVFoundation
import CoreImage
import EditorKit
import SharedKit

/// A frame-by-frame export pipeline that composites effects (zoom, cursor, background)
/// into the output video using `FrameCompositor`.
///
/// Use this instead of `MP4Exporter` when the recording project contains effects that
/// must be baked into the exported file (e.g. background style, zoom segments).
public enum CompositorExporter {

    // MARK: - Public API

    /// Export a source video, compositing all project effects frame-by-frame.
    ///
    /// - Parameters:
    ///   - source: URL of the raw `.mov` / `.mp4` source video.
    ///   - project: Editor project containing trim, zoom, and background style.
    ///   - cursorTimeline: Precomputed smoothed cursor positions, or `nil` to skip cursor overlay.
    ///   - zoomInterpolator: Precomputed zoom interpolator, or `nil` to skip zoom effects.
    ///   - destination: Output file URL (will be overwritten if it exists).
    ///   - quality: H.264 encoding quality preset.
    ///   - progress: Optional progress callback in `[0, 1]` range, called on the calling actor.
    /// - Returns: The `destination` URL on success.
    public static func export(
        source: URL,
        project: RecordingProject,
        cursorTimeline: SmoothedCursorTimeline?,
        zoomInterpolator: ZoomInterpolator?,
        destination: URL,
        quality: ExportQuality,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {

        // MARK: Asset + track inspection

        let asset = AVURLAsset(url: source)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.exportSessionFailed("No video track found in source file")
        }

        let naturalSize  = try await videoTrack.load(.naturalSize)
        let nominalFPS   = try await videoTrack.load(.nominalFrameRate)
        let duration     = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        // MARK: FrameCompositor

        let compositor = FrameCompositor(
            sourceSize: naturalSize,
            backgroundStyle: project.backgroundStyle,
            outputScale: 1.0
        )
        let outputSize = compositor.outputSize

        // MARK: CIContext (GPU-accelerated)

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // MARK: AVAssetReader setup — one reader per media type
        //
        // We use SEPARATE AVAssetReader instances for video and audio.
        // A single reader cannot be reliably read in two independent loops:
        // once the video loop drains the reader to .completed, the audio
        // output's buffer queue may be exhausted or the reader refuses to
        // produce more samples, resulting in silent exported files.

        guard let videoReader = try? AVAssetReader(asset: asset) else {
            throw ExportError.exportSessionFailed("Could not create AVAssetReader for video")
        }

        // Video: decode to BGRA pixels
        let videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: videoOutputSettings
        )
        videoOutput.alwaysCopiesSampleData = false
        guard videoReader.canAdd(videoOutput) else {
            throw ExportError.exportSessionFailed("Cannot add video reader output")
        }
        videoReader.add(videoOutput)

        // Audio: passthrough (nil outputSettings = compressed passthrough)
        // Uses its own dedicated AVAssetReader so it can be read independently
        // of the video loop without the two competing for the same reader state.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderTrackOutput?
        var audioReader: AVAssetReader?
        if let audioTrack = audioTracks.first,
           let ar = try? AVAssetReader(asset: asset) {
            let ao = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            ao.alwaysCopiesSampleData = false
            if ar.canAdd(ao) {
                ar.add(ao)
                audioOutput = ao
                audioReader = ar
            }
        }

        // MARK: AVAssetWriter setup

        // Remove existing output file if present
        try? FileManager.default.removeItem(at: destination)

        guard let writer = try? AVAssetWriter(outputURL: destination, fileType: .mp4) else {
            throw ExportError.exportSessionFailed("Could not create AVAssetWriter")
        }

        // Video input — H.264 with quality-scaled bitrate
        let bitrate = Self.bitrate(for: quality, size: outputSize, fps: Double(nominalFPS))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw ExportError.exportSessionFailed("Cannot add video writer input")
        }
        writer.add(videoInput)

        // Audio input — passthrough
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            ai.expectsMediaDataInRealTime = false
            if writer.canAdd(ai) {
                writer.add(ai)
                audioInput = ai
            }
        }

        // MARK: Start reading + writing

        guard videoReader.startReading() else {
            throw ExportError.exportSessionFailed("AVAssetReader (video) failed to start: \(videoReader.error?.localizedDescription ?? "unknown")")
        }
        if let audioReader {
            guard audioReader.startReading() else {
                throw ExportError.exportSessionFailed("AVAssetReader (audio) failed to start: \(audioReader.error?.localizedDescription ?? "unknown")")
            }
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // MARK: Video frame loop

        let trimRegions = project.trimRegions

        while let sampleBuffer = videoOutput.copyNextSampleBuffer() {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timeSec = CMTimeGetSeconds(presentationTime)

            // Skip frames that fall inside a trim region
            if isTimeTrimmed(timeSec, trimRegions: trimRegions) {
                continue
            }

            // Report progress (capped at 0.95 — the final 5% is finalization)
            if totalSeconds > 0 {
                progress?(min(0.95, timeSec / totalSeconds))
            }

            // Wait until the writer input is ready
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }

            // Decode pixel buffer → CIImage
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Compute zoom transform + cursor position at this timestamp
            let zoomTransform: FrameTransform
            let cursorPos: CGPoint?

            if let interp = zoomInterpolator, let timeline = cursorTimeline {
                let rawCursor = timeline.position(at: timeSec)
                let transform = interp.transform(
                    at: timeSec,
                    cursorPosition: (x: rawCursor.x, y: rawCursor.y)
                )
                zoomTransform = transform
                cursorPos = CGPoint(x: rawCursor.x, y: rawCursor.y)
            } else if let interp = zoomInterpolator {
                zoomTransform = interp.transform(at: timeSec, cursorPosition: nil)
                cursorPos = nil
            } else {
                zoomTransform = .identity
                cursorPos = cursorTimeline.map {
                    let p = $0.position(at: timeSec)
                    return CGPoint(x: p.x, y: p.y)
                }
            }

            // Composite the frame
            let composited = compositor.compose(
                frame: sourceImage,
                zoomTransform: zoomTransform,
                cursorPosition: cursorPos,
                cursorImage: nil   // cursor image overlay not yet wired (telemetry only)
            )

            // Render CIImage → CVPixelBuffer
            guard let pool = adaptor.pixelBufferPool else {
                throw ExportError.exportSessionFailed("Pixel buffer pool unavailable")
            }
            var outputBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
            guard status == kCVReturnSuccess, let outputBuffer else {
                throw ExportError.exportSessionFailed("Failed to allocate output pixel buffer: \(status)")
            }

            ciContext.render(composited, to: outputBuffer)

            adaptor.append(outputBuffer, withPresentationTime: presentationTime)
        }

        // MARK: Audio passthrough loop

        if let audioOutput, let audioInput {
            while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let timeSec = CMTimeGetSeconds(presentationTime)

                if isTimeTrimmed(timeSec, trimRegions: trimRegions) {
                    continue
                }

                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(10))
                }

                audioInput.append(sampleBuffer)
            }
            audioInput.markAsFinished()
        }

        videoInput.markAsFinished()

        // MARK: Finalize

        if videoReader.status == .failed {
            throw ExportError.exportSessionFailed("AVAssetReader (video) failed: \(videoReader.error?.localizedDescription ?? "unknown")")
        }
        if let audioReader, audioReader.status == .failed {
            throw ExportError.exportSessionFailed("AVAssetReader (audio) failed: \(audioReader.error?.localizedDescription ?? "unknown")")
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.exportSessionFailed("AVAssetWriter failed: \(writer.error?.localizedDescription ?? "unknown")")
        }

        progress?(1.0)
        return destination
    }

    // MARK: - Private helpers

    /// Returns `true` if `time` falls within any of the given trim regions.
    private static func isTimeTrimmed(_ time: TimeInterval, trimRegions: [TrimRegion]) -> Bool {
        for region in trimRegions {
            if time >= region.startTime && time < region.endTime {
                return true
            }
        }
        return false
    }

    /// Computes an H.264 target bitrate in bits/second, scaling by resolution and frame rate.
    ///
    /// Base rates (in bits/s) at 1080p / 30 fps:
    /// - maximum:  8 Mbps
    /// - social:   5 Mbps
    /// - web:      3 Mbps
    private static func bitrate(for quality: ExportQuality, size: CGSize, fps: Double) -> Int {
        let baseRate: Double = switch quality {
        case .maximum: 8_000_000
        case .social:  5_000_000
        case .web:     3_000_000
        }

        let referencePixels = 1920.0 * 1080.0
        let actualPixels    = Double(size.width) * Double(size.height)
        let pixelScale      = actualPixels / referencePixels

        let fpsFactor = (fps > 0 ? fps : 30) / 30.0

        return Int(baseRate * pixelScale * fpsFactor)
    }
}
