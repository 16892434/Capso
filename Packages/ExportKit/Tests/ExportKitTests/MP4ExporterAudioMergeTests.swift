import AVFoundation
import Foundation
import SharedKit
import Testing

@testable import ExportKit

/// Regression coverage for https://github.com/lzhgus/Capso/issues/55
///
/// When both system audio and microphone are captured, Capso writes two
/// separate AAC tracks into the raw `.mov`. Most consumer tools (Slack,
/// Linear, macOS Services re-encode) only read the first audio track, so
/// the exported `.mp4` must merge them into a single mixed track.
struct MP4ExporterAudioMergeTests {
    @Test
    func exportMergesDualAudioTracksIntoOne() async throws {
        let source = try DualAudioFixture.make()
        defer { try? FileManager.default.removeItem(at: source) }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue55-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: dest) }

        let exported = try await VideoExporter.export(
            source: source,
            options: ExportOptions(format: .mp4, quality: .maximum, destination: dest)
        )

        let asset = AVURLAsset(url: exported)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        #expect(audioTracks.count == 1, "Exported file must contain a single audio track")
        #expect(videoTracks.count == 1, "Exported file must contain a single video track")
    }

    @Test
    func exportPreservesSingleAudioTrack() async throws {
        let source = try DualAudioFixture.make(audioTrackCount: 1)
        defer { try? FileManager.default.removeItem(at: source) }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue55-single-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: dest) }

        let exported = try await VideoExporter.export(
            source: source,
            options: ExportOptions(format: .mp4, quality: .maximum, destination: dest)
        )

        let asset = AVURLAsset(url: exported)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        #expect(audioTracks.count == 1)
    }
}
