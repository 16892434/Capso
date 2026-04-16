import SwiftUI
import AVKit
@preconcurrency import EditorKit

/// Video preview with real-time zoom, background, and cursor effects.
///
/// Uses MetalPreviewView (MTKView + CIContext) for GPU-accelerated rendering
/// of the composited frame on every display frame.
struct EditorPreviewView: View {
    let coordinator: EditorCoordinator

    var body: some View {
        MetalPreviewView(
            player: coordinator.player,
            playerItem: coordinator.playerItem,
            backgroundStyle: coordinator.project.backgroundStyle,
            zoomSegments: coordinator.project.zoomSegments,
            videoSize: coordinator.project.videoSize,
            cursorTimeline: coordinator.cursorTimeline
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
