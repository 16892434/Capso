import AppKit
import AVFoundation
import AVKit
import Observation
import EditorKit
import EffectsKit
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

    // MARK: - Window lifecycle

    /// Called when the editor should close itself (e.g. after a successful export).
    /// Set by the owner (RecordingCoordinator) to tear down the window.
    var onClose: (() -> Void)?

    func closeEditor() {
        onClose?()
    }

    // MARK: - Private

    nonisolated(unsafe) private var timeObserver: Any?
    let playerItem: AVPlayerItem

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
        let start = effectiveStartTime
        let end = effectiveEndTime

        // Determine where to begin playback
        var playFrom = currentTime

        // If at or past effective end, restart from beginning
        if playFrom >= end - 0.05 {
            playFrom = start + 0.1
        }
        // If at or before effective start (inside head trim), jump past it
        else if playFrom <= start + 0.05 {
            playFrom = start + 0.1
        }

        let cmTime = CMTime(seconds: playFrom, preferredTimescale: 600)
        let capturedTime = playFrom
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [capturedTime] in
                self.currentTime = capturedTime
                self.player.play()
                self.isPlaying = true
            }
        }
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

    // MARK: - Zoom Segments

    var selectedZoomSegmentID: UUID?

    var selectedZoomSegment: ZoomSegment? {
        guard let id = selectedZoomSegmentID else { return nil }
        return project.zoomSegments.first { $0.id == id }
    }

    func addZoomSegment(at time: TimeInterval) {
        let dur = min(3.0, self.duration - time)
        guard dur > 0.5 else { return }
        let segment = ZoomSegment(startTime: time, endTime: time + dur, zoomLevel: 1.5, focusMode: .followCursor)
        project.zoomSegments.append(segment)
        selectedZoomSegmentID = segment.id
    }

    func removeZoomSegment(id: UUID) {
        project.zoomSegments.removeAll { $0.id == id }
        if selectedZoomSegmentID == id { selectedZoomSegmentID = nil }
    }

    func moveZoomSegment(id: UUID, to newStart: TimeInterval) {
        guard let index = project.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        let dur = project.zoomSegments[index].duration
        let clamped = max(0, min(duration - dur, newStart))
        project.zoomSegments[index].startTime = clamped
        project.zoomSegments[index].endTime = clamped + dur
    }

    func resizeZoomSegment(id: UUID, newStart: TimeInterval? = nil, newEnd: TimeInterval? = nil) {
        guard let index = project.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        if let newStart {
            project.zoomSegments[index].startTime = max(0, min(project.zoomSegments[index].endTime - 0.5, newStart))
        }
        if let newEnd {
            project.zoomSegments[index].endTime = min(duration, max(project.zoomSegments[index].startTime + 0.5, newEnd))
        }
    }

    func setZoomLevel(id: UUID, level: Double) {
        guard let index = project.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        project.zoomSegments[index].zoomLevel = max(1.25, min(5.0, level))
    }

    func setZoomFocusMode(id: UUID, mode: ZoomFocusMode) {
        guard let index = project.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        project.zoomSegments[index].focusMode = mode
    }

    // MARK: - Cursor Timeline (cached)

    private var _cursorTimeline: SmoothedCursorTimeline?
    private var _cursorTimelineBuilt = false

    var cursorTimeline: SmoothedCursorTimeline? {
        if !_cursorTimelineBuilt {
            _cursorTimelineBuilt = true
            if project.cursorSmoothing.enabled, let url = project.cursorTelemetryURL {
                if let data = try? CursorTelemetry.load(from: url) {
                    let smoother = CursorSmoother(telemetry: data, config: project.cursorSmoothing)
                    _cursorTimeline = smoother.buildSmoothedTimeline(fps: 60, duration: project.videoDuration)
                }
            }
        }
        return _cursorTimeline
    }

    // MARK: - Export

    /// Use CompositorExporter when visual effects need to be baked into the export.
    var hasCompositingEffects: Bool {
        project.backgroundStyle.enabled || !project.zoomSegments.isEmpty
    }

    func exportVideo(format: ExportFormat, quality: ExportQuality, destination: URL) async throws -> URL {
        isExporting = true
        exportProgress = 0
        defer { isExporting = false }

        if hasCompositingEffects {
            return try await exportWithCompositor(format: format, quality: quality, destination: destination)
        } else {
            // Build a time range from trim handles (head/tail trim)
            let start = effectiveStartTime
            let end = effectiveEndTime
            let trimRange: CMTimeRange?
            if start > 0.01 || end < duration - 0.01 {
                let cmStart = CMTime(seconds: start, preferredTimescale: 600)
                let cmDuration = CMTime(seconds: end - start, preferredTimescale: 600)
                trimRange = CMTimeRange(start: cmStart, duration: cmDuration)
            } else {
                trimRange = nil
            }

            let options = ExportOptions(format: format, quality: quality, destination: destination, timeRange: trimRange)
            return try await VideoExporter.export(
                source: project.sourceVideoURL,
                options: options
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.exportProgress = progress
                }
            }
        }
    }

    private func exportWithCompositor(
        format: ExportFormat,
        quality: ExportQuality,
        destination: URL
    ) async throws -> URL {
        var cursorTimeline: SmoothedCursorTimeline?
        if project.cursorSmoothing.enabled, let telemetryURL = project.cursorTelemetryURL {
            if let telemetryData = try? CursorTelemetry.load(from: telemetryURL) {
                let smoother = CursorSmoother(
                    telemetry: telemetryData,
                    config: project.cursorSmoothing
                )
                cursorTimeline = smoother.buildSmoothedTimeline(
                    fps: 60,
                    duration: project.videoDuration
                )
            }
        }

        var zoomInterpolator: ZoomInterpolator?
        if !project.zoomSegments.isEmpty {
            zoomInterpolator = ZoomInterpolator(
                segments: project.zoomSegments,
                frameSize: project.videoSize
            )
        }

        return try await CompositorExporter.export(
            source: project.sourceVideoURL,
            project: project,
            cursorTimeline: cursorTimeline,
            zoomInterpolator: zoomInterpolator,
            destination: destination,
            quality: quality
        ) { [weak self] progress in
            Task { @MainActor in
                self?.exportProgress = progress
            }
        }
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
                guard self.isPlaying else { return }
                let time = cmTime.seconds
                let adjusted = self.skipTrimRegions(from: time)
                // Only seek if we're meaningfully inside a trim region (>0.05s difference).
                // Small differences are floating-point noise at boundaries.
                if adjusted - time > 0.05 {
                    self.seek(to: adjusted)
                    return
                }
                self.currentTime = time
                if time >= self.effectiveEndTime - 0.03 {
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
