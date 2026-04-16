import SwiftUI
import EditorKit

struct RecordingEditorView: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    EditorPreviewView(
                        player: coordinator.player,
                        backgroundStyle: coordinator.project.backgroundStyle
                    )
                    .padding(16)
                    .animation(Animation.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
                    .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.padding)
                    .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.cornerRadius)
                    .animation(Animation.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                EditorSettingsPanel(coordinator: coordinator)
                    .frame(width: 260)
            }
            .frame(maxHeight: .infinity)

            Divider()

            VStack(spacing: 8) {
                EditorPlaybackControls(coordinator: coordinator)
                EditorTimelineView(coordinator: coordinator)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 180)
        }
    }
}
