import SwiftUI
import AVKit
@preconcurrency import EditorKit

/// Wraps AVPlayerView with live background effect preview.
/// Background settings (padding, corners, shadow, color) are visualized
/// as SwiftUI decorations around the video player so users see changes instantly.
struct EditorPreviewView: View {
    let player: AVPlayer
    let backgroundStyle: EditorKit.BackgroundStyle

    var body: some View {
        if backgroundStyle.enabled {
            previewWithBackground
        } else {
            PlayerView(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var previewWithBackground: some View {
        // Background canvas with the selected color/gradient
        ZStack {
            // Background fill
            backgroundFill
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Video frame with padding, corners, and shadow
            PlayerView(player: player)
                .clipShape(RoundedRectangle(cornerRadius: backgroundStyle.cornerRadius))
                .shadow(
                    color: backgroundStyle.shadowEnabled
                        ? .black.opacity(backgroundStyle.shadowOpacity)
                        : .clear,
                    radius: backgroundStyle.shadowEnabled
                        ? backgroundStyle.shadowRadius
                        : 0,
                    y: backgroundStyle.shadowEnabled
                        ? backgroundStyle.shadowRadius * 0.3
                        : 0
                )
                .padding(backgroundStyle.padding)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch backgroundStyle.colorType {
        case .solid:
            let c = backgroundStyle.solidColor
            Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        case .gradient:
            let from = backgroundStyle.gradientFrom
            let to = backgroundStyle.gradientTo
            LinearGradient(
                colors: [
                    Color(red: from.red, green: from.green, blue: from.blue),
                    Color(red: to.red, green: to.green, blue: to.blue),
                ],
                startPoint: gradientStartPoint,
                endPoint: gradientEndPoint
            )
        case .liquidGlass:
            // Live preview: a second player view, heavily blurred, acts as backdrop.
            // The actual export uses CIFilter-based compositing for pixel-perfect result.
            PlayerView(player: player)
                .scaleEffect(1.15) // overshoot so blur doesn't reveal edges
                .blur(radius: 40)
                .saturation(1.8)
                .contrast(0.95)
                .allowsHitTesting(false)
        }
    }

    private var gradientStartPoint: UnitPoint {
        let angle = backgroundStyle.gradientAngle
        return UnitPoint(
            x: 0.5 - cos(angle * .pi / 180) * 0.5,
            y: 0.5 - sin(angle * .pi / 180) * 0.5
        )
    }

    private var gradientEndPoint: UnitPoint {
        let angle = backgroundStyle.gradientAngle
        return UnitPoint(
            x: 0.5 + cos(angle * .pi / 180) * 0.5,
            y: 0.5 + sin(angle * .pi / 180) * 0.5
        )
    }
}

/// Raw AVPlayerView wrapper as NSViewRepresentable.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        // Make background transparent so the selected background color/effect shows
        // through instead of the default black letterbox bars.
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        // Also set the video gravity to resize-aspect-fill to avoid letterboxing
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
