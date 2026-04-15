import SwiftUI

struct EditorPlaybackControls: View {
    let coordinator: EditorCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { coordinator.togglePlayback() }) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(coordinator.formatTime(coordinator.currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(coordinator.formatTime(coordinator.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            if coordinator.isExporting {
                ProgressView(value: coordinator.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                    .controlSize(.small)
                Text("\(Int(coordinator.exportProgress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Button("Export") {
                    // Will be wired later
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}
