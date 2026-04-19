import SwiftUI
import AVKit
@preconcurrency import EditorKit

/// Video preview with real-time zoom (Metal) + background effects (SwiftUI).
///
/// Architecture:
/// - Zoom: rendered in real-time via MetalPreviewView (AVPlayerItemVideoOutput → CIImage → FrameCompositor zoom only → MTKView)
/// - Background: SwiftUI decorations (padding, color, shadow, corners) — reliable and flicker-free
///
/// The FrameCompositor in the Metal renderer is configured with background DISABLED
/// so it only applies zoom transforms. Background styling is handled by the SwiftUI layer.
struct EditorPreviewView: View {
    let coordinator: EditorCoordinator

    private var bg: EditorKit.BackgroundStyle {
        coordinator.project.backgroundStyle
    }

    private var frameCornerRadius: CGFloat {
        CGFloat(bg.clampedCornerRadius(for: coordinator.project.videoSize))
    }

    /// Video aspect ratio for constraining the preview area
    private var videoAspectRatio: CGFloat {
        let size = coordinator.project.videoSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    /// Aspect ratio including background padding
    private var compositeAspectRatio: CGFloat {
        let size = coordinator.project.videoSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        let pad = bg.padding * 2
        return (size.width + pad) / (size.height + pad)
    }

    var body: some View {
        if bg.enabled {
            previewWithBackground
                .aspectRatio(compositeAspectRatio, contentMode: .fit)
        } else {
            metalPreview(cornerRadius: 4)
                .aspectRatio(videoAspectRatio, contentMode: .fit)
        }
    }

    /// Metal preview configured for zoom-only (no background compositing).
    ///
    /// Corner rounding is applied INSIDE `MetalPreviewView` at the CAMetalLayer
    /// level rather than via `.clipShape` — SwiftUI's clipShape on a
    /// Metal-backed NSViewRepresentable can leave one or more edges
    /// un-clipped (users reported the top corners rounded but the right
    /// side rendered as a straight vertical line).
    private func metalPreview(cornerRadius: CGFloat) -> some View {
        MetalPreviewView(
            player: coordinator.player,
            playerItem: coordinator.playerItem,
            backgroundStyle: EditorKit.BackgroundStyle(enabled: false), // zoom only
            zoomSegments: coordinator.project.zoomSegments,
            videoSize: coordinator.project.videoSize,
            cursorTimeline: coordinator.cursorTimeline,
            cursorCIImage: coordinator.cursorCIImage,
            cursorOverlayProvider: coordinator.cursorOverlayProvider,
            cornerRadius: cornerRadius
        )
    }

    /// Concentric outer radius: the band of background padding between the
    /// video and the outer frame has uniform thickness only if the outer
    /// corner grows by `padding`. Otherwise the padding bulges at the
    /// corners — the user correctly spotted this looking broken at
    /// padding=16 with a hardcoded outer radius.
    private var outerCornerRadius: CGFloat {
        frameCornerRadius + CGFloat(bg.padding)
    }

    private var previewWithBackground: some View {
        ZStack {
            backgroundFill
                .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))

            metalPreview(cornerRadius: frameCornerRadius)
                .shadow(
                    color: bg.shadowEnabled
                        ? .black.opacity(bg.shadowOpacity)
                        : .clear,
                    radius: bg.shadowEnabled ? bg.shadowRadius : 0,
                    y: bg.shadowEnabled ? bg.shadowRadius * 0.3 : 0
                )
                .padding(bg.padding)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch bg.colorType {
        case .solid:
            Color(red: bg.solidColor.red, green: bg.solidColor.green, blue: bg.solidColor.blue, opacity: bg.solidColor.alpha)
        case .gradient:
            LinearGradient(
                colors: [
                    Color(red: bg.gradientFrom.red, green: bg.gradientFrom.green, blue: bg.gradientFrom.blue),
                    Color(red: bg.gradientTo.red, green: bg.gradientTo.green, blue: bg.gradientTo.blue),
                ],
                startPoint: gradientStartPoint,
                endPoint: gradientEndPoint
            )
        case .liquidGlass:
            // Second player view blurred as backdrop — same as before, proven to work
            MetalPreviewView(
                player: coordinator.player,
                playerItem: coordinator.playerItem,
                backgroundStyle: EditorKit.BackgroundStyle(enabled: false),
                zoomSegments: [],
                videoSize: coordinator.project.videoSize,
                cursorTimeline: nil,
                cursorCIImage: nil,
                cursorOverlayProvider: nil
            )
            .scaleEffect(1.15)
            .blur(radius: 40)
            .saturation(1.8)
            .contrast(0.95)
            .allowsHitTesting(false)
        }
    }

    private var gradientStartPoint: UnitPoint {
        let angle = bg.gradientAngle
        return UnitPoint(
            x: 0.5 - cos(angle * .pi / 180) * 0.5,
            y: 0.5 - sin(angle * .pi / 180) * 0.5
        )
    }

    private var gradientEndPoint: UnitPoint {
        let angle = bg.gradientAngle
        return UnitPoint(
            x: 0.5 + cos(angle * .pi / 180) * 0.5,
            y: 0.5 + sin(angle * .pi / 180) * 0.5
        )
    }
}
