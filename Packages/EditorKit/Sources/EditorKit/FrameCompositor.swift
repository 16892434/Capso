// Packages/EditorKit/Sources/EditorKit/FrameCompositor.swift

import CoreImage
import CoreGraphics
import Foundation

/// Composites a single video frame with optional zoom transform, cursor overlay,
/// and decorative background canvas.
///
/// `FrameCompositor` is a pure value-oriented pipeline — it holds no mutable state
/// and can safely be called from any actor or thread (hence `Sendable`).
public final class FrameCompositor: Sendable {

    // MARK: - Stored Properties

    private let sourceSize: CGSize
    private let backgroundStyle: BackgroundStyle
    private let scale: CGFloat

    // MARK: - Computed Properties

    /// The pixel dimensions of the composited output image.
    ///
    /// When `backgroundStyle.enabled` is `true` the canvas adds `2 × padding` to
    /// both axes (scaled by `outputScale`).  Dimensions are always rounded up to the
    /// nearest even integer so the result can be fed directly into a video encoder.
    public let outputSize: CGSize

    // MARK: - Init

    /// - Parameters:
    ///   - sourceSize: The pixel dimensions of the raw video frames.
    ///   - backgroundStyle: Background canvas configuration.
    ///   - outputScale: Display scale factor (e.g. 2.0 for Retina).  All padding /
    ///     radius values are multiplied by this factor before rendering.
    public init(sourceSize: CGSize, backgroundStyle: BackgroundStyle, outputScale: CGFloat) {
        self.sourceSize = sourceSize
        self.backgroundStyle = backgroundStyle
        self.scale = outputScale
        self.outputSize = Self.computeOutputSize(
            sourceSize: sourceSize,
            backgroundStyle: backgroundStyle,
            outputScale: outputScale
        )
    }

    // MARK: - Public API

    /// Composites one video frame and returns the resulting `CIImage`.
    ///
    /// The pipeline is:
    /// 1. Apply zoom transform (scale + translate) and crop back to source viewport.
    /// 2. Composite the cursor image at the given normalized position (if provided).
    /// 3. Optionally apply rounded corners.
    /// 4. Optionally add a drop shadow.
    /// 5. Composite the frame onto the background canvas.
    ///
    /// - Parameters:
    ///   - frame: Raw video frame.  Its `extent` should match `sourceSize`.
    ///   - zoomTransform: Scale + translation to apply before compositing.
    ///   - cursorPosition: Normalized (0–1, 0–1) position of the cursor in the source
    ///     frame.  Y=0 is the *top* of the frame (screen coordinate space); the
    ///     compositor flips to Core Image's bottom-left origin internally.
    ///   - cursorImage: The cursor image to overlay.  Its origin is placed at the
    ///     converted position.  Pass `nil` to skip cursor compositing.
    /// - Returns: The fully composited `CIImage` with extent starting at `(0, 0)` and
    ///   having dimensions equal to `outputSize`.
    public func compose(
        frame: CIImage,
        zoomTransform: FrameTransform,
        cursorPosition: CGPoint?,
        cursorImage: CIImage?
    ) -> CIImage {
        // 1. Zoom
        var result = applyZoom(to: frame, transform: zoomTransform)

        // 2. Cursor overlay
        if let position = cursorPosition, let cursor = cursorImage {
            result = applyCursor(cursor, at: position, over: result)
        }

        // 3 – 5. Background
        if backgroundStyle.enabled {
            result = applyBackground(to: result)
        }

        return result
    }

    // MARK: - Private: Zoom

    private func applyZoom(to image: CIImage, transform: FrameTransform) -> CIImage {
        guard transform != .identity else { return image }

        let w = sourceSize.width
        let h = sourceSize.height
        let s = CGFloat(transform.scale)
        let tx = CGFloat(transform.translateX)
        let ty = CGFloat(transform.translateY)

        // Build an affine transform that scales around the frame centre then translates.
        let centerX = w / 2.0
        let centerY = h / 2.0

        let affine = CGAffineTransform.identity
            .translatedBy(x: centerX, y: centerY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -centerX, y: -centerY)
            .translatedBy(x: tx, y: ty)

        let zoomed = image.transformed(by: affine)

        // Crop back to the original source viewport so the output size stays fixed.
        let viewport = CGRect(x: 0, y: 0, width: w, height: h)
        return zoomed.cropped(to: viewport)
    }

    // MARK: - Private: Cursor

    private func applyCursor(_ cursor: CIImage, at position: CGPoint, over background: CIImage) -> CIImage {
        let w = sourceSize.width
        let h = sourceSize.height

        // `position` uses top-left origin (screen coords); CIImage uses bottom-left.
        let x = position.x * w
        let y = (1.0 - position.y) * h

        // Centre the cursor image on the position.
        let cx = cursor.extent.width / 2.0
        let cy = cursor.extent.height / 2.0
        let placed = cursor.transformed(by: CGAffineTransform(translationX: x - cx, y: y - cy))

        // Composite cursor over frame, clamped to source bounds.
        return placed.composited(over: background).cropped(to: background.extent)
    }

    // MARK: - Private: Background

    private func applyBackground(to frame: CIImage) -> CIImage {
        let padding = CGFloat(backgroundStyle.padding) * scale
        let canvasSize = outputSize
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        // Position the frame centred inside the canvas (padding on all four sides).
        let frameOrigin = CGPoint(x: padding, y: padding)
        let frameRect = CGRect(origin: frameOrigin, size: sourceSize)

        // 1. Optionally apply rounded corners to the frame image.
        let roundedFrame = applyRoundedCorners(to: frame, frameRect: frameRect)

        // 2. Optionally create a drop shadow underneath the frame.
        var composite: CIImage

        // 3. Build the background canvas.
        let canvas = buildCanvas(in: canvasRect, sourceFrame: frame)

        if backgroundStyle.shadowEnabled && backgroundStyle.shadowOpacity > 0 {
            let shadow = buildShadow(frameRect: frameRect)
            // shadow beneath canvas content, frame on top
            composite = roundedFrame
                .composited(over: shadow)
                .composited(over: canvas)
        } else {
            composite = roundedFrame.composited(over: canvas)
        }

        return composite.cropped(to: canvasRect)
    }

    /// Applies rounded corners to the frame by using `CIRoundedRectangleGenerator`
    /// as a mask via `CIBlendWithMask`.
    private func applyRoundedCorners(to frame: CIImage, frameRect: CGRect) -> CIImage {
        let radius = CGFloat(backgroundStyle.cornerRadius) * scale
        guard radius > 0 else {
            // No rounding — just translate the frame to its canvas position.
            return frame.transformed(by: CGAffineTransform(translationX: frameRect.origin.x, y: frameRect.origin.y))
        }

        // Translate the frame to its position on the canvas.
        let positioned = frame.transformed(by: CGAffineTransform(translationX: frameRect.origin.x, y: frameRect.origin.y))

        // Build the rounded-rect mask.
        let mask = makeRoundedRectMask(rect: frameRect, radius: radius)

        // CIBlendWithMask: composites `inputImage` over `inputBackgroundImage` using `inputMaskImage`.
        // We want: `positioned` where mask is white, transparent elsewhere.
        let transparent = CIImage.empty()
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return positioned
        }
        blendFilter.setValue(positioned, forKey: kCIInputImageKey)
        blendFilter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        return blendFilter.outputImage ?? positioned
    }

    /// Creates a white rounded-rect `CIImage` suitable for use as an alpha mask.
    private func makeRoundedRectMask(rect: CGRect, radius: CGFloat) -> CIImage {
        // Try the Core Image generator first (available macOS 14+).
        if let filter = CIFilter(name: "CIRoundedRectangleGenerator") {
            filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
            filter.setValue(radius, forKey: "inputRadius")
            filter.setValue(CIColor.white, forKey: "inputColor")
            if let output = filter.outputImage {
                return output.cropped(to: rect)
            }
        }

        // Fallback: draw into a CGContext and convert.
        return makeRoundedRectMaskViaCGContext(rect: rect, radius: radius)
    }

    /// Fallback rounded-rect mask drawn via CGContext.
    private func makeRoundedRectMaskViaCGContext(rect: CGRect, radius: CGFloat) -> CIImage {
        let w = Int(rect.width)
        let h = Int(rect.height)
        guard w > 0, h > 0 else { return CIImage.empty() }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return CIImage.empty() }

        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        // The path is in the context's local space (origin at bottom-left, same as CIImage).
        let localRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        let path = CGPath(roundedRect: localRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else { return CIImage.empty() }
        // Translate to match the canvas position of the frame.
        let ci = CIImage(cgImage: cgImage)
        return ci.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
    }

    // MARK: - Private: Shadow

    private func buildShadow(frameRect: CGRect) -> CIImage {
        let blurRadius = CGFloat(backgroundStyle.shadowRadius) * scale
        let opacity = CGFloat(backgroundStyle.shadowOpacity)

        // Create a solid-black rectangle matching the frame footprint.
        let shadowColor = CIColor(red: 0, green: 0, blue: 0, alpha: opacity)
        let blackRect = CIImage(color: shadowColor).cropped(to: frameRect)

        // Blur it to simulate a drop shadow.
        guard blurRadius > 0,
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return blackRect
        }
        // Clamp before blur to prevent edge artifacts
        let clamped = blackRect.clampedToExtent()
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        let blurred = blurFilter.outputImage ?? blackRect

        // The blur expands the image; crop it back to a reasonable bounding region.
        let expansion = blurRadius * 3
        let shadowRect = frameRect.insetBy(dx: -expansion, dy: -expansion)
        return blurred.cropped(to: shadowRect)
    }

    // MARK: - Private: Canvas

    private func buildCanvas(in rect: CGRect, sourceFrame: CIImage) -> CIImage {
        switch backgroundStyle.colorType {
        case .solid:
            let c = backgroundStyle.solidColor
            let color = CIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
            return CIImage(color: color).cropped(to: rect)

        case .gradient:
            return buildGradientCanvas(in: rect)

        case .liquidGlass:
            return buildLiquidGlassCanvas(in: rect, sourceFrame: sourceFrame)
        }
    }

    /// Blurred, saturation-boosted copy of the source frame scaled to fill the canvas.
    private func buildLiquidGlassCanvas(in rect: CGRect, sourceFrame: CIImage) -> CIImage {
        let srcExtent = sourceFrame.extent
        guard srcExtent.width > 0, srcExtent.height > 0 else {
            return CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: rect)
        }

        // Aspect-fill scale with overshoot so blur edges stay inside canvas
        let coverScale = max(rect.width / srcExtent.width, rect.height / srcExtent.height) * 1.15
        var ci = sourceFrame.transformed(by: CGAffineTransform(scaleX: coverScale, y: coverScale))

        // Centre on canvas
        let tx = rect.midX - ci.extent.midX
        let ty = rect.midY - ci.extent.midY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation for richer glass-like colour bloom
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.9,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.95,
        ]), let out = f.outputImage {
            ci = out
        }

        // Clamp before blur to prevent edge fade
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 120.0,
        ]), let out = f.outputImage {
            ci = out
        }

        return ci.cropped(to: rect)
    }

    private func buildGradientCanvas(in rect: CGRect) -> CIImage {
        // Convert angle (degrees, 0 = top-to-bottom) to a start/end point pair.
        // Angle 0° → from top centre to bottom centre.
        let angleRad = CGFloat(backgroundStyle.gradientAngle) * .pi / 180.0

        let cx = rect.midX
        let cy = rect.midY
        // Half-diagonal so the gradient covers the full rect at any angle.
        let halfLen = hypot(rect.width, rect.height) / 2.0

        // `sin` drives X, `-cos` drives Y (angle 0 = straight down in screen space,
        // which is straight up in CIImage's flipped Y space → use +cos for CIImage Y).
        let dx = sin(angleRad) * halfLen
        let dy = cos(angleRad) * halfLen

        let point0 = CIVector(x: cx - dx, y: cy - dy)
        let point1 = CIVector(x: cx + dx, y: cy + dy)

        let from = backgroundStyle.gradientFrom
        let to   = backgroundStyle.gradientTo
        let color0 = CIColor(red: from.red, green: from.green, blue: from.blue, alpha: from.alpha)
        let color1 = CIColor(red: to.red,   green: to.green,   blue: to.blue,   alpha: to.alpha)

        guard let gradFilter = CIFilter(name: "CILinearGradient") else {
            // Fallback: solid color using gradientFrom.
            return CIImage(color: color0).cropped(to: rect)
        }
        gradFilter.setValue(point0, forKey: "inputPoint0")
        gradFilter.setValue(point1, forKey: "inputPoint1")
        gradFilter.setValue(color0, forKey: "inputColor0")
        gradFilter.setValue(color1, forKey: "inputColor1")

        let gradient = gradFilter.outputImage ?? CIImage(color: color0)
        return gradient.cropped(to: rect)
    }

    // MARK: - Private: Output size computation

    private static func computeOutputSize(
        sourceSize: CGSize,
        backgroundStyle: BackgroundStyle,
        outputScale: CGFloat
    ) -> CGSize {
        guard backgroundStyle.enabled else { return sourceSize }

        let padding = CGFloat(backgroundStyle.padding) * outputScale
        let rawWidth  = sourceSize.width  + 2 * padding
        let rawHeight = sourceSize.height + 2 * padding

        // Round up to even numbers (required by most video codecs).
        let w = CGFloat(Self.roundUpToEven(rawWidth))
        let h = CGFloat(Self.roundUpToEven(rawHeight))
        return CGSize(width: w, height: h)
    }

    /// Rounds a floating-point value up to the nearest even integer.
    private static func roundUpToEven(_ value: CGFloat) -> Int {
        let i = Int(ceil(value))
        return i % 2 == 0 ? i : i + 1
    }
}
