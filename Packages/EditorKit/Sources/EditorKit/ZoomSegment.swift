// Packages/EditorKit/Sources/EditorKit/ZoomSegment.swift

import Foundation

/// Determines how the zoom focus point is calculated during a zoom segment.
public enum ZoomFocusMode: Codable, Sendable, Equatable {
    /// The zoom center tracks the cursor position in real time.
    case followCursor
    /// The zoom is locked to a fixed normalized position (0–1 range).
    case manual(x: Double, y: Double)
}

/// A time-bounded segment of the video that applies a zoom effect.
public struct ZoomSegment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    /// Zoom magnification level. 1.0 = no zoom, 2.0 = 2× magnification.
    public var zoomLevel: Double
    /// How the zoom focus point is determined.
    public var focusMode: ZoomFocusMode

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        zoomLevel: Double = 1.5,
        focusMode: ZoomFocusMode = .followCursor
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.zoomLevel = zoomLevel
        self.focusMode = focusMode
    }

    /// Duration of the zoom segment in seconds.
    public var duration: TimeInterval { endTime - startTime }
}
