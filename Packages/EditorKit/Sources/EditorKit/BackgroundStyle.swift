// Packages/EditorKit/Sources/EditorKit/BackgroundStyle.swift

import Foundation

/// Background fill type for the area behind the video frame.
public enum BackgroundColorType: String, Codable, Sendable {
    case solid
    case gradient
    /// Blurred, saturation-boosted copy of the video frame as backdrop.
    case liquidGlass
}

/// A Codable, platform-agnostic color representation using normalized RGBA components.
public struct CodableColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = CodableColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let darkGray = CodableColor(red: 0.2, green: 0.2, blue: 0.2)
}

/// Describes the decorative background rendered behind the video in the editor output.
public struct BackgroundStyle: Codable, Sendable, Equatable {
    /// When `false`, the video is rendered without any background decoration.
    public var enabled: Bool
    public var colorType: BackgroundColorType
    public var solidColor: CodableColor
    public var gradientFrom: CodableColor
    public var gradientTo: CodableColor
    /// Angle of the gradient in degrees (0 = top-to-bottom).
    public var gradientAngle: Double
    /// Padding around the video content, in points (0–80).
    public var padding: Double
    /// Corner radius applied to the video frame (0–24).
    public var cornerRadius: Double
    public var shadowEnabled: Bool
    /// Blur radius of the drop shadow (0–30).
    public var shadowRadius: Double
    /// Opacity of the drop shadow (0–1).
    public var shadowOpacity: Double

    public init(
        enabled: Bool = false,
        colorType: BackgroundColorType = .solid,
        solidColor: CodableColor = .darkGray,
        gradientFrom: CodableColor = .black,
        gradientTo: CodableColor = .darkGray,
        gradientAngle: Double = 135.0,
        padding: Double = 20.0,
        cornerRadius: Double = 12.0,
        shadowEnabled: Bool = true,
        shadowRadius: Double = 15.0,
        shadowOpacity: Double = 0.5
    ) {
        self.enabled = enabled
        self.colorType = colorType
        self.solidColor = solidColor
        self.gradientFrom = gradientFrom
        self.gradientTo = gradientTo
        self.gradientAngle = gradientAngle
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowEnabled = shadowEnabled
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }

    /// Default background style with sensible initial values.
    public static let `default` = BackgroundStyle()
}
