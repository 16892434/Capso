import SwiftUI

struct EditorTimelineView: View {
    let coordinator: EditorCoordinator

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 40)

                let progress = coordinator.duration > 0
                    ? coordinator.currentTime / coordinator.duration
                    : 0.0
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 50)
                    .offset(x: progress * geo.size.width)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 60)
    }
}
