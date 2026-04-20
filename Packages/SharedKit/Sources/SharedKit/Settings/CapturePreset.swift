import CoreGraphics
import Foundation

/// A capture size constraint: freeform, locked aspect ratio, or fixed pixel dimensions.
public enum CapturePreset: Codable, Hashable, Sendable {
    case freeform
    case aspectRatio(width: Int, height: Int, name: String?)
    case fixedSize(width: Int, height: Int, name: String?)
}

// MARK: - Identifiable

extension CapturePreset: Identifiable {
    public var id: String {
        switch self {
        case .freeform:
            return "freeform"
        case .aspectRatio(let w, let h, _):
            return "ratio-\(w)-\(h)"
        case .fixedSize(let w, let h, _):
            return "fixed-\(w)-\(h)"
        }
    }
}

// MARK: - Display

extension CapturePreset {
    /// Human-readable label for menus and badges.
    public var displayName: String {
        switch self {
        case .freeform:
            return "Freeform"
        case .aspectRatio(let w, let h, let name):
            let ratio = "\(w):\(h)"
            if let name { return "\(ratio) (\(name))" }
            return ratio
        case .fixedSize(let w, let h, let name):
            let size = "\(w) × \(h)"
            if let name { return "\(size) (\(name))" }
            return size
        }
    }

    /// Short badge text shown next to the dimension label during capture.
    public var badgeText: String? {
        switch self {
        case .freeform:
            return nil
        case .aspectRatio(let w, let h, _):
            return "\(w):\(h)"
        case .fixedSize:
            return "Fixed"
        }
    }

    /// True when the preset defines exact pixel dimensions (no drag needed).
    public var isFixedSize: Bool {
        if case .fixedSize = self { return true }
        return false
    }

    /// The aspect ratio as a CGFloat (width / height), or nil for freeform.
    public var ratio: CGFloat? {
        switch self {
        case .freeform:
            return nil
        case .aspectRatio(let w, let h, _):
            return CGFloat(w) / CGFloat(h)
        case .fixedSize(let w, let h, _):
            return CGFloat(w) / CGFloat(h)
        }
    }

    /// The fixed pixel size, or nil for freeform/ratio presets.
    public var fixedPixelSize: (width: Int, height: Int)? {
        if case .fixedSize(let w, let h, _) = self {
            return (w, h)
        }
        return nil
    }
}

// MARK: - Built-in Presets

extension CapturePreset {
    public static let builtinAspectRatios: [CapturePreset] = [
        .freeform,
        .aspectRatio(width: 1, height: 1, name: "Square"),
        .aspectRatio(width: 4, height: 3, name: nil),
        .aspectRatio(width: 16, height: 9, name: nil),
        .aspectRatio(width: 3, height: 2, name: nil),
    ]

    public static let builtinFixedSizes: [CapturePreset] = [
        .fixedSize(width: 512, height: 512, name: nil),
        .fixedSize(width: 1280, height: 720, name: "720p"),
        .fixedSize(width: 1920, height: 1080, name: "1080p"),
    ]

    public static let allBuiltins: [CapturePreset] = builtinAspectRatios + builtinFixedSizes
}
