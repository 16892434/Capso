import SwiftUI
import AVFoundation
import MetalKit
@preconcurrency import EditorKit

/// A SwiftUI view that wraps an `MTKView` to display a Metal-composited video preview.
///
/// Unlike `AVPlayerView`, this view runs every frame through `FrameCompositor`, which
/// applies zoom transforms, background styles, and cursor overlays in real time via
/// Core Image and Metal.
///
/// Usage: swap `EditorPreviewView` for `MetalPreviewView` in `RecordingEditorView`.
struct MetalPreviewView: NSViewRepresentable {

    // MARK: - Properties

    let player: AVPlayer
    let playerItem: AVPlayerItem
    let backgroundStyle: EditorKit.BackgroundStyle
    let zoomSegments: [ZoomSegment]
    let videoSize: CGSize
    let cursorTimeline: SmoothedCursorTimeline?

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        var renderer: MetalPreviewRenderer?
        var videoOutput: AVPlayerItemVideoOutput?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()

        // Pixel format must match what CIContext expects when rendering to the texture.
        view.colorPixelFormat = .bgra8Unorm

        // CIContext.render(_:to:commandBuffer:...) requires write access to the texture,
        // which is blocked when framebufferOnly == true.
        view.framebufferOnly = false

        // Continuous rendering at ~30 fps — smooth enough for a preview without hammering GPU.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30

        // Build the AVPlayerItemVideoOutput that the renderer will poll each frame.
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        playerItem.add(videoOutput)
        context.coordinator.videoOutput = videoOutput

        // Create the renderer; if Metal is unavailable, leave delegate nil (black view).
        if let renderer = MetalPreviewRenderer(player: player, videoOutput: videoOutput) {
            renderer.updateCompositor(sourceSize: videoSize, backgroundStyle: backgroundStyle)
            renderer.updateZoom(segments: zoomSegments, frameSize: videoSize)
            renderer.updateCursorTimeline(cursorTimeline)
            view.device = MTLCreateSystemDefaultDevice()
            view.delegate = renderer
            context.coordinator.renderer = renderer
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.updateCompositor(sourceSize: videoSize, backgroundStyle: backgroundStyle)
        renderer.updateZoom(segments: zoomSegments, frameSize: videoSize)
        renderer.updateCursorTimeline(cursorTimeline)
    }
}
