// Packages/EditorKit/Sources/EditorKit/RecordingProject.swift

import Foundation

// MARK: - CursorSmoothingConfig

/// Spring physics parameters for smoothing cursor movement during playback/export.
public struct CursorSmoothingConfig: Codable, Sendable {
    /// When `false`, raw cursor positions are used without smoothing.
    public var enabled: Bool
    /// Spring stiffness coefficient. Higher = snappier response.
    public var stiffness: Double
    /// Damping coefficient. Controls oscillation decay.
    public var damping: Double
    /// Mass of the simulated cursor point. Higher = more sluggish.
    public var mass: Double

    public init(
        enabled: Bool = true,
        stiffness: Double = 120,
        damping: Double = 14,
        mass: Double = 1.0
    ) {
        self.enabled = enabled
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
    }

    /// Fast, responsive smoothing preset.
    public static let snappy = CursorSmoothingConfig(stiffness: 400, damping: 30, mass: 1.0)
    /// Balanced smoothing (default).
    public static let smooth = CursorSmoothingConfig()
    /// Slow, floaty smoothing.
    public static let floaty = CursorSmoothingConfig(stiffness: 50, damping: 10, mass: 2.0)
}

// MARK: - RecordingProject

/// The top-level model representing all editor state for a single recorded video.
///
/// Serialized to JSON and stored alongside the source video file.
///
/// `CGSize` does not conform to `Codable`, so this type provides manual encoding/decoding
/// that stores width and height as separate JSON keys.
public struct RecordingProject: Codable, Sendable {
    public var id: UUID
    /// URL of the source `.mov` or `.mp4` file from the recorder.
    public var sourceVideoURL: URL
    /// Optional URL of the cursor telemetry JSON file written by the recorder.
    public var cursorTelemetryURL: URL?
    /// Total duration of the source video in seconds.
    public var videoDuration: TimeInterval
    /// Pixel dimensions of the source video.
    public var videoSize: CGSize
    /// The recording area size in display points (may differ from videoSize on HiDPI).
    public var recordingAreaSize: CGSize
    /// Regions that have been cut from the timeline.
    public var trimRegions: [TrimRegion]
    /// Time-bounded zoom effects overlaid on the video.
    public var zoomSegments: [ZoomSegment]
    /// Background decoration style applied in the final export.
    public var backgroundStyle: BackgroundStyle
    /// Cursor motion smoothing parameters.
    public var cursorSmoothing: CursorSmoothingConfig
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceVideoURL: URL,
        cursorTelemetryURL: URL? = nil,
        videoDuration: TimeInterval,
        videoSize: CGSize,
        recordingAreaSize: CGSize,
        trimRegions: [TrimRegion] = [],
        zoomSegments: [ZoomSegment] = [],
        backgroundStyle: BackgroundStyle = .default,
        cursorSmoothing: CursorSmoothingConfig = .smooth,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceVideoURL = sourceVideoURL
        self.cursorTelemetryURL = cursorTelemetryURL
        self.videoDuration = videoDuration
        self.videoSize = videoSize
        self.recordingAreaSize = recordingAreaSize
        self.trimRegions = trimRegions
        self.zoomSegments = zoomSegments
        self.backgroundStyle = backgroundStyle
        self.cursorSmoothing = cursorSmoothing
        self.createdAt = createdAt
    }

    /// The playback/export duration after all trim regions are removed.
    ///
    /// Guaranteed to be non-negative.
    public var effectiveDuration: TimeInterval {
        let trimmed = trimRegions.reduce(0.0) { $0 + $1.duration }
        return max(0, videoDuration - trimmed)
    }

    // MARK: - Codable (manual — CGSize is not Codable)

    private enum CodingKeys: String, CodingKey {
        case id, sourceVideoURL, cursorTelemetryURL, videoDuration
        case videoSizeWidth, videoSizeHeight
        case recordingAreaWidth, recordingAreaHeight
        case trimRegions, zoomSegments, backgroundStyle, cursorSmoothing, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceVideoURL = try c.decode(URL.self, forKey: .sourceVideoURL)
        cursorTelemetryURL = try c.decodeIfPresent(URL.self, forKey: .cursorTelemetryURL)
        videoDuration = try c.decode(TimeInterval.self, forKey: .videoDuration)
        let vsW = try c.decode(Double.self, forKey: .videoSizeWidth)
        let vsH = try c.decode(Double.self, forKey: .videoSizeHeight)
        videoSize = CGSize(width: vsW, height: vsH)
        let raW = try c.decode(Double.self, forKey: .recordingAreaWidth)
        let raH = try c.decode(Double.self, forKey: .recordingAreaHeight)
        recordingAreaSize = CGSize(width: raW, height: raH)
        trimRegions = try c.decode([TrimRegion].self, forKey: .trimRegions)
        zoomSegments = try c.decode([ZoomSegment].self, forKey: .zoomSegments)
        backgroundStyle = try c.decode(BackgroundStyle.self, forKey: .backgroundStyle)
        cursorSmoothing = try c.decode(CursorSmoothingConfig.self, forKey: .cursorSmoothing)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceVideoURL, forKey: .sourceVideoURL)
        try c.encodeIfPresent(cursorTelemetryURL, forKey: .cursorTelemetryURL)
        try c.encode(videoDuration, forKey: .videoDuration)
        try c.encode(videoSize.width, forKey: .videoSizeWidth)
        try c.encode(videoSize.height, forKey: .videoSizeHeight)
        try c.encode(recordingAreaSize.width, forKey: .recordingAreaWidth)
        try c.encode(recordingAreaSize.height, forKey: .recordingAreaHeight)
        try c.encode(trimRegions, forKey: .trimRegions)
        try c.encode(zoomSegments, forKey: .zoomSegments)
        try c.encode(backgroundStyle, forKey: .backgroundStyle)
        try c.encode(cursorSmoothing, forKey: .cursorSmoothing)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Persistence

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Serializes the project to a JSON file at the given URL.
    public func save(to url: URL) throws {
        let data = try Self.encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Deserializes a project from a JSON file at the given URL.
    public static func load(from url: URL) throws -> RecordingProject {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RecordingProject.self, from: data)
    }
}
