import AppKit
import AVFoundation
import AVKit
import Observation
import EditorKit
import ExportKit
import SharedKit

@MainActor @Observable
final class EditorCoordinator {

    // MARK: - Project

    var project: RecordingProject

    // MARK: - Playback

    let player: AVPlayer
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    // MARK: - Export state

    var isExporting: Bool = false
    var exportProgress: Double = 0

    // MARK: - Private

    private var timeObserver: Any?
    private let playerItem: AVPlayerItem

    // MARK: - Init

    init(project: RecordingProject) {
        self.project = project
        let asset = AVURLAsset(url: project.sourceVideoURL)
        self.playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.duration = project.videoDuration

        setupTimeObserver()
        setupEndObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Playback Controls

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        if currentTime >= effectiveEndTime {
            seek(to: effectiveStartTime)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        let adjusted = skipTrimRegions(from: clamped)
        let cmTime = CMTime(seconds: adjusted, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = adjusted
    }

    // MARK: - Trim

    var effectiveStartTime: TimeInterval {
        project.trimRegions
            .filter { $0.startTime < 0.01 }
            .map(\.endTime)
            .max() ?? 0
    }

    var effectiveEndTime: TimeInterval {
        project.trimRegions
            .filter { $0.endTime >= duration - 0.01 }
            .map(\.startTime)
            .min() ?? duration
    }

    func setHeadTrim(to time: TimeInterval) {
        project.trimRegions.removeAll { $0.startTime < 0.01 }
        if time > 0.01 {
            project.trimRegions.append(
                TrimRegion(startTime: 0, endTime: min(time, duration))
            )
        }
        if currentTime < time {
            seek(to: time)
        }
    }

    func setTailTrim(to time: TimeInterval) {
        project.trimRegions.removeAll { $0.endTime >= duration - 0.01 }
        if time < duration - 0.01 {
            project.trimRegions.append(
                TrimRegion(startTime: max(0, time), endTime: duration)
            )
        }
        if currentTime > time {
            seek(to: time)
        }
    }

    func addTrimRegion(start: TimeInterval, end: TimeInterval) {
        guard end > start else { return }
        project.trimRegions.append(TrimRegion(startTime: start, endTime: end))
        if currentTime >= start && currentTime < end {
            seek(to: end)
        }
    }

    func removeTrimRegion(id: UUID) {
        project.trimRegions.removeAll { $0.id == id }
    }

    func skipTrimRegions(from time: TimeInterval) -> TimeInterval {
        var result = time
        let sorted = project.trimRegions.sorted { $0.startTime < $1.startTime }
        for trim in sorted {
            if result >= trim.startTime && result < trim.endTime {
                result = trim.endTime
            }
        }
        return min(result, duration)
    }

    // MARK: - Export

    func exportVideo(format: ExportFormat, quality: ExportQuality, destination: URL) async throws -> URL {
        isExporting = true
        exportProgress = 0
        defer { isExporting = false }

        let options = ExportOptions(format: format, quality: quality, destination: destination)
        let result = try await VideoExporter.export(
            source: project.sourceVideoURL,
            options: options
        ) { [weak self] progress in
            Task { @MainActor in
                self?.exportProgress = progress
            }
        }
        return result
    }

    // MARK: - Time Formatting

    func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }

    // MARK: - Private

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            guard let self else { return }
            Task { @MainActor in
                let time = cmTime.seconds
                let adjusted = self.skipTrimRegions(from: time)
                if adjusted != time {
                    self.seek(to: adjusted)
                    return
                }
                self.currentTime = time
                if time >= self.effectiveEndTime {
                    self.pause()
                    self.currentTime = self.effectiveEndTime
                }
            }
        }
    }

    private func setupEndObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pause()
            }
        }
    }
}
