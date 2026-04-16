// Packages/ExportKit/Sources/ExportKit/ExportOptions.swift
import Foundation
import CoreMedia
import SharedKit

public enum ExportFormat: String, Sendable {
    case mp4
    case gif
}

public struct ExportOptions: Sendable {
    public let format: ExportFormat
    public let quality: ExportQuality
    public let destination: URL
    /// Optional time range to export. When set, only this portion of the source is exported.
    public let timeRange: CMTimeRange?

    public init(format: ExportFormat, quality: ExportQuality, destination: URL, timeRange: CMTimeRange? = nil) {
        self.format = format
        self.quality = quality
        self.destination = destination
        self.timeRange = timeRange
    }
}

public enum ExportError: Error, Sendable {
    case sourceFileNotFound
    case exportSessionFailed(String)
    case frameExtractionFailed
    case gifCreationFailed
    case cancelled
}
