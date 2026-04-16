// Packages/ExportKit/Sources/ExportKit/CompositorExporter.swift

import Foundation
import AVFoundation
import CoreImage
import EditorKit
import SharedKit

/// Exports a recording with visual effects (background, zoom) baked in.
///
/// Uses `AVAssetExportSession` with a `AVMutableVideoComposition` that applies
/// CIFilter-based compositing per frame. This is Apple's recommended approach
/// for applying Core Image effects during export — it handles audio passthrough,
/// frame timing, and encoding automatically. Much more reliable than manual
/// AVAssetReader/Writer pipelines.
public enum CompositorExporter {

    public static func export(
        source: URL,
        project: RecordingProject,
        cursorTimeline: SmoothedCursorTimeline?,
        zoomInterpolator: ZoomInterpolator?,
        destination: URL,
        quality: ExportQuality,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {

        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.frameExtractionFailed
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let fps = nominalFPS > 0 ? nominalFPS : 30.0

        // Set up compositor
        let compositor = FrameCompositor(
            sourceSize: naturalSize,
            backgroundStyle: project.backgroundStyle,
            outputScale: 1.0
        )
        let outSize = compositor.outputSize
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // Trim regions for time remapping
        let sortedTrims = project.trimRegions.sorted { $0.startTime < $1.startTime }

        // Create a video composition that applies effects per frame
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let sourceImage = request.sourceImage.clampedToExtent()
            let timeSec = request.compositionTime.seconds

            // Compute zoom transform
            let cursorPos = cursorTimeline?.position(at: timeSec)
            let zoomTransform: FrameTransform
            if let interp = zoomInterpolator {
                let cp = cursorPos.map { (x: $0.x, y: $0.y) }
                zoomTransform = interp.transform(at: timeSec, cursorPosition: cp)
            } else {
                zoomTransform = .identity
            }

            // Composite the frame
            let cgCursorPos = cursorPos.map { CGPoint(x: $0.x, y: $0.y) }
            let composited = compositor.compose(
                frame: sourceImage.cropped(to: CGRect(origin: .zero, size: naturalSize)),
                zoomTransform: zoomTransform,
                cursorPosition: cgCursorPos,
                cursorImage: nil
            )

            // Ensure output matches expected size
            let outputRect = CGRect(origin: .zero, size: outSize)
            let finalImage = composited.cropped(to: outputRect)

            request.finish(with: finalImage, context: ciContext)
        }

        // Set output size and frame rate
        videoComposition.renderSize = outSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Choose export preset
        let presetName = switch quality {
        case .maximum: AVAssetExportPresetHighestQuality
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ExportError.exportSessionFailed("Could not create export session")
        }

        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        // Apply trim as time range if present
        let effectiveStart = sortedTrims.filter { $0.startTime < 0.01 }.map(\.endTime).max() ?? 0
        let duration = try await asset.load(.duration).seconds
        let effectiveEnd = sortedTrims.filter { $0.endTime >= duration - 0.01 }.map(\.startTime).min() ?? duration

        if effectiveStart > 0.01 || effectiveEnd < duration - 0.01 {
            let cmStart = CMTime(seconds: effectiveStart, preferredTimescale: 600)
            let cmDuration = CMTime(seconds: effectiveEnd - effectiveStart, preferredTimescale: 600)
            session.timeRange = CMTimeRange(start: cmStart, duration: cmDuration)
        }

        // Remove existing file
        try? FileManager.default.removeItem(at: destination)

        // Export
        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            throw ExportError.cancelled
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }

        progress?(1.0)
        return destination
    }
}
