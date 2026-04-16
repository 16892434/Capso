// Packages/ExportKit/Sources/ExportKit/CompositorExporter.swift

import Foundation
import AVFoundation
import CoreImage
import EditorKit
import SharedKit

/// Exports a recording with visual effects (background, zoom) baked in.
///
/// Uses `AVMutableVideoComposition` with a CIFilter handler for per-frame
/// compositing via `FrameCompositor`. Audio is passed through automatically
/// by `AVAssetExportSession`.
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

        let compositor = FrameCompositor(
            sourceSize: naturalSize,
            backgroundStyle: project.backgroundStyle,
            outputScale: 1.0
        )
        let outSize = compositor.outputSize
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // Build the video composition with per-frame CIFilter handler
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Use the customVideoCompositorClass approach is complex; instead use
        // the simpler CIFilter handler. But we must create it properly.
        let filterComposition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                let sourceImage = request.sourceImage
                let timeSec = request.compositionTime.seconds
                let sourceRect = CGRect(origin: .zero, size: naturalSize)

                // Compute zoom
                let cursorPos = cursorTimeline?.position(at: timeSec)
                let zoomTransform: FrameTransform
                if let interp = zoomInterpolator {
                    let cp = cursorPos.map { (x: $0.x, y: $0.y) }
                    zoomTransform = interp.transform(at: timeSec, cursorPosition: cp)
                } else {
                    zoomTransform = .identity
                }

                // Composite
                let cgCursorPos = cursorPos.map { CGPoint(x: $0.x, y: $0.y) }
                let composited = compositor.compose(
                    frame: sourceImage.cropped(to: sourceRect),
                    zoomTransform: zoomTransform,
                    cursorPosition: cgCursorPos,
                    cursorImage: nil
                )

                // Ensure output extent starts at origin and matches renderSize
                let outputRect = CGRect(origin: .zero, size: outSize)
                let finalImage = composited.cropped(to: outputRect)

                request.finish(with: finalImage, context: ciContext)
            }
        )

        // Override renderSize and frameDuration on the composition returned by
        // the convenience initializer (it defaults to naturalSize)
        filterComposition.renderSize = outSize
        filterComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Export preset
        let presetName = switch quality {
        case .maximum: AVAssetExportPresetHighestQuality
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ExportError.exportSessionFailed("Could not create export session")
        }

        session.videoComposition = filterComposition
        session.shouldOptimizeForNetworkUse = true

        // Apply trim
        let sortedTrims = project.trimRegions.sorted { $0.startTime < $1.startTime }
        let effectiveStart = sortedTrims.filter { $0.startTime < 0.01 }.map(\.endTime).max() ?? 0
        let duration = try await asset.load(.duration).seconds
        let effectiveEnd = sortedTrims.filter { $0.endTime >= duration - 0.01 }.map(\.startTime).min() ?? duration

        if effectiveStart > 0.01 || effectiveEnd < duration - 0.01 {
            let cmStart = CMTime(seconds: effectiveStart, preferredTimescale: 600)
            let cmDuration = CMTime(seconds: effectiveEnd - effectiveStart, preferredTimescale: 600)
            session.timeRange = CMTimeRange(start: cmStart, duration: cmDuration)
        }

        try? FileManager.default.removeItem(at: destination)

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
