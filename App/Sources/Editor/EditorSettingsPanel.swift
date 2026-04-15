import SwiftUI

struct EditorSettingsPanel: View {
    let coordinator: EditorCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 4)

                Text("Background, zoom, and cursor settings will be added in a later step.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}
