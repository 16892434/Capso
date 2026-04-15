import SwiftUI
import EditorKit

struct RecordingEditorView: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    EditorPreviewView(player: coordinator.player)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                EditorSettingsPanel(coordinator: coordinator)
                    .frame(width: 220)
            }
            .frame(maxHeight: .infinity)

            Divider()

            VStack(spacing: 8) {
                EditorPlaybackControls(coordinator: coordinator)
                EditorTimelineView(coordinator: coordinator)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 140)
        }
    }
}
