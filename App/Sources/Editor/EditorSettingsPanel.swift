import SwiftUI
import EditorKit
import SharedKit

struct EditorSettingsPanel: View {
    @Bindable var coordinator: EditorCoordinator

    @State private var lastAutoZoomRun: AutoZoomRunResult = .idle
    @State private var autoZoomRevertTask: Task<Void, Never>?

    private enum AutoZoomRunResult: Equatable {
        case idle
        case ranEmpty   // 0 segments — show inline "no moments" hint for a few seconds
        case ranNonEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Effects")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 4)

                backgroundSection
                zoomSection
                cursorSection
            }
            .padding(16)
        }
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Background")

            settingCard {
                settingToggleRow(
                    "Enabled",
                    isOn: $coordinator.project.backgroundStyle.enabled
                )

                if coordinator.project.backgroundStyle.enabled {
                    cardDivider

                    // Color type picker
                    settingPickerRow("Style", selection: $coordinator.project.backgroundStyle.colorType) {
                        Text("Solid").tag(BackgroundColorType.solid)
                        Text("Gradient").tag(BackgroundColorType.gradient)
                        Text("Liquid Glass").tag(BackgroundColorType.liquidGlass)
                    }

                    cardDivider

                    // Color presets (only for solid fills)
                    if coordinator.project.backgroundStyle.colorType == .solid {
                        colorPresetRow
                    }

                    cardDivider

                    // Padding — vertical layout for full-width slider
                    verticalSliderRow(
                        "Padding",
                        value: $coordinator.project.backgroundStyle.padding,
                        range: 0...80,
                        unit: "px"
                    )

                    // Corner radius
                    verticalSliderRow(
                        "Corner Radius",
                        value: $coordinator.project.backgroundStyle.cornerRadius,
                        range: 0...24,
                        unit: "px"
                    )

                    cardDivider

                    // Shadow
                    settingToggleRow(
                        "Shadow",
                        isOn: $coordinator.project.backgroundStyle.shadowEnabled
                    )

                    if coordinator.project.backgroundStyle.shadowEnabled {
                        verticalSliderRow(
                            "Shadow Radius",
                            value: $coordinator.project.backgroundStyle.shadowRadius,
                            range: 0...30,
                            unit: "px"
                        )

                        verticalSliderRow(
                            "Shadow Opacity",
                            value: $coordinator.project.backgroundStyle.shadowOpacity,
                            range: 0...1,
                            unit: "",
                            precision: 2,
                            step: 0.05
                        )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
            .animation(.easeInOut(duration: 0.15), value: coordinator.project.backgroundStyle.shadowEnabled)
        }
    }

    // MARK: - Color Presets

    private var colorPresetRow: some View {
        HStack(spacing: 8) {
            colorPresetButton(.darkGray, label: "Dark")
            colorPresetButton(CodableColor(red: 0.95, green: 0.95, blue: 0.95), label: "Light")
            colorPresetButton(.black, label: "Black")
            colorPresetButton(CodableColor(red: 0.15, green: 0.2, blue: 0.35), label: "Navy")
            colorPresetButton(CodableColor(red: 0.2, green: 0.12, blue: 0.25), label: "Plum")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func colorPresetButton(_ color: CodableColor, label: String) -> some View {
        let isSelected = coordinator.project.backgroundStyle.solidColor == color
        return Button {
            coordinator.project.backgroundStyle.solidColor = color
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 32, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.white.opacity(0.15),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cursor Section

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Cursor")

            settingCard {
                settingToggleRow(
                    "Smoothing",
                    isOn: $coordinator.project.cursorSmoothing.enabled
                )

                if coordinator.project.cursorSmoothing.enabled {
                    cardDivider

                    settingPickerRow("Style", selection: smoothingPresetBinding) {
                        Text("Snappy").tag(CursorSmoothingPreset.snappy)
                        Text("Smooth").tag(CursorSmoothingPreset.smooth)
                        Text("Floaty").tag(CursorSmoothingPreset.floaty)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.cursorSmoothing.enabled)
        }
    }

    // MARK: - Smoothing Preset

    private var smoothingPresetBinding: Binding<CursorSmoothingPreset> {
        Binding(
            get: {
                coordinator.project.cursorSmoothing.preset
            },
            set: { preset in
                coordinator.project.cursorSmoothing = preset.config
            }
        )
    }

    // MARK: - Zoom Section

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Zoom")

            settingCard {
                autoZoomRow

                cardDivider

                HStack {
                    Text("Segments")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(coordinator.project.zoomSegments.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let segment = coordinator.selectedZoomSegment {
                    cardDivider

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Segment")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    verticalSliderRow(
                        "Zoom Level",
                        value: zoomLevelBinding(for: segment.id),
                        range: 1.25...5.0,
                        unit: "x",
                        precision: 1,
                        step: 0.25
                    )

                    settingPickerRow("Focus", selection: focusModeBinding(for: segment.id)) {
                        Text("Follow Cursor").tag(ZoomFocusTag.followCursor)
                        Text("Center").tag(ZoomFocusTag.center)
                    }

                    cardDivider

                    Button(role: .destructive) {
                        coordinator.removeZoomSegment(id: segment.id)
                    } label: {
                        Label("Delete Segment", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                } else {
                    cardDivider

                    Text("Double-click the zoom track to add segments.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var autoZoomRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("Suggest zooms")
                    .font(.system(size: 13))
                Spacer()
                autoZoomButton
            }

            Text(autoZoomSubtext)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .animation(.easeInOut(duration: 0.2), value: lastAutoZoomRun)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var autoZoomSubtext: String {
        switch lastAutoZoomRun {
        case .ranEmpty:
            return "No clear moments detected — try recording with more clicks."
        case .idle, .ranNonEmpty:
            return "Analyzes clicks + pauses."
        }
    }

    private var autoZoomButton: some View {
        Button {
            let count = coordinator.autoZoom()
            lastAutoZoomRun = count > 0 ? .ranNonEmpty : .ranEmpty
            autoZoomRevertTask?.cancel()
            if count == 0 {
                autoZoomRevertTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    if lastAutoZoomRun == .ranEmpty {
                        lastAutoZoomRun = .idle
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                Text("Detect")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.purple.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.purple.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.canAutoZoom)
        .opacity(coordinator.canAutoZoom ? 1.0 : 0.4)
    }

    private enum ZoomFocusTag {
        case followCursor, center
    }

    private func zoomLevelBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { coordinator.project.zoomSegments.first { $0.id == id }?.zoomLevel ?? 1.5 },
            set: { coordinator.setZoomLevel(id: id, level: $0) }
        )
    }

    private func focusModeBinding(for id: UUID) -> Binding<ZoomFocusTag> {
        Binding(
            get: {
                guard let seg = coordinator.project.zoomSegments.first(where: { $0.id == id }) else { return .followCursor }
                if case .followCursor = seg.focusMode { return .followCursor }
                return .center
            },
            set: { tag in
                switch tag {
                case .followCursor: coordinator.setZoomFocusMode(id: id, mode: .followCursor)
                case .center: coordinator.setZoomFocusMode(id: id, mode: .manual(x: 0.5, y: 0.5))
                }
            }
        )
    }

    // MARK: - Reusable Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.leading, 2)
    }

    private var cardDivider: some View {
        Divider().background(Color.white.opacity(0.06))
    }

    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func settingToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
    }

    /// Vertical layout slider: label + value on top row, full-width slider below.
    /// This gives the slider track maximum width for easy dragging.
    private func verticalSliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        precision: Int = 0,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if precision > 0 {
                    Text(String(format: "%.\(precision)f\(unit)", value.wrappedValue))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(Int(value.wrappedValue))\(unit)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func settingPickerRow<SelectionValue: Hashable, Content: View>(
        _ label: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .frame(width: 110)
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
