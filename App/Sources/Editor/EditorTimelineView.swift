import SwiftUI
import EditorKit

struct EditorTimelineView: View {
    @Bindable var coordinator: EditorCoordinator
    @State private var isDraggingPlayhead = false

    var body: some View {
        VStack(spacing: 6) {
            trimRegionRow

            GeometryReader { geo in
                let trackWidth = geo.size.width
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))

                    // Trim regions (shaded)
                    ForEach(coordinator.project.trimRegions) { trim in
                        let startX = timeToX(trim.startTime, in: trackWidth)
                        let endX = timeToX(trim.endTime, in: trackWidth)
                        Rectangle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: max(1, endX - startX))
                            .offset(x: startX)
                    }

                    // Head trim handle
                    trimHandle(
                        time: coordinator.effectiveStartTime,
                        trackWidth: trackWidth,
                        edge: .leading
                    ) { newTime in
                        coordinator.setHeadTrim(to: newTime)
                    }

                    // Tail trim handle
                    trimHandle(
                        time: coordinator.effectiveEndTime,
                        trackWidth: trackWidth,
                        edge: .trailing
                    ) { newTime in
                        coordinator.setTailTrim(to: newTime)
                    }

                    // Playhead
                    playhead(trackWidth: trackWidth)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let time = xToTime(location.x, in: trackWidth)
                    coordinator.seek(to: time)
                }
            }
            .frame(height: 40)

            timeMarkers
        }
    }

    // MARK: - Playhead

    private func playhead(trackWidth: Double) -> some View {
        let x = timeToX(coordinator.currentTime, in: trackWidth)
        return ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 48)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
                .offset(y: -24)
        }
        .offset(x: x - 1)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDraggingPlayhead = true
                    if coordinator.isPlaying { coordinator.pause() }
                    let time = xToTime(value.location.x, in: trackWidth)
                    coordinator.seek(to: time)
                }
                .onEnded { _ in
                    isDraggingPlayhead = false
                }
        )
    }

    // MARK: - Trim Handles

    private func trimHandle(
        time: TimeInterval,
        trackWidth: Double,
        edge: HorizontalEdge,
        onDrag: @escaping (TimeInterval) -> Void
    ) -> some View {
        let x = timeToX(time, in: trackWidth)
        let handleWidth: Double = 8
        let offset = edge == .leading ? x - handleWidth : x

        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange.opacity(0.8))
            .frame(width: handleWidth, height: 44)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newTime = xToTime(value.location.x, in: trackWidth)
                        let clamped = max(0, min(coordinator.duration, newTime))
                        onDrag(clamped)
                    }
            )
            .help(edge == .leading ? "Drag to trim start" : "Drag to trim end")
    }

    // MARK: - Trim Region Row

    private var trimRegionRow: some View {
        HStack {
            let segmentTrims = coordinator.project.trimRegions.filter {
                $0.startTime > 0.01 && $0.endTime < coordinator.duration - 0.01
            }
            if !segmentTrims.isEmpty {
                Text("\(segmentTrims.count) trimmed segment\(segmentTrims.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if coordinator.project.effectiveDuration < coordinator.duration {
                Text("Duration: \(coordinator.formatTime(coordinator.project.effectiveDuration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Time Markers

    private var timeMarkers: some View {
        HStack {
            Text(coordinator.formatTime(0))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer()
            Text(coordinator.formatTime(coordinator.duration / 2))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
            Spacer()
            Text(coordinator.formatTime(coordinator.duration))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Coordinate Conversion

    private func timeToX(_ time: TimeInterval, in width: Double) -> Double {
        guard coordinator.duration > 0 else { return 0 }
        return (time / coordinator.duration) * width
    }

    private func xToTime(_ x: Double, in width: Double) -> TimeInterval {
        guard width > 0 else { return 0 }
        return (x / width) * coordinator.duration
    }
}
