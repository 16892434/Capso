// Packages/ExportKit/Sources/ExportKit/MP4Exporter.swift
import Foundation
import AVFoundation
import SharedKit

enum MP4Exporter {
    static func export(
        source: URL,
        quality: ExportQuality,
        destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)

        let presetName = switch quality {
        case .maximum: AVAssetExportPresetPassthrough
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        // For social/web, check if source is already <= target resolution.
        // If so, use passthrough to avoid unnecessary re-encode.
        let effectivePreset: String
        if quality != .maximum {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let targetWidth: CGFloat = quality == .social ? 1920 : 1280
                if size.width <= targetWidth {
                    effectivePreset = AVAssetExportPresetPassthrough
                } else {
                    effectivePreset = presetName
                }
            } else {
                effectivePreset = presetName
            }
        } else {
            effectivePreset = presetName
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: effectivePreset) else {
            throw ExportError.exportSessionFailed("Could not create export session with preset \(effectivePreset)")
        }

        session.shouldOptimizeForNetworkUse = true

        // AVAssetExportSession cannot overwrite existing files
        try? FileManager.default.removeItem(at: destination)

        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            throw ExportError.cancelled
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }

        progress?(1.0)
        return destination
    }
}
