import SwiftUI
import EditorKit
import SharedKit

struct EditorSettingsPanel: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Effects")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 4)

                backgroundSection
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
                    }

                    cardDivider

                    // Color presets
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
                        Text("Snappy").tag(SmoothingPreset.snappy)
                        Text("Smooth").tag(SmoothingPreset.smooth)
                        Text("Floaty").tag(SmoothingPreset.floaty)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.cursorSmoothing.enabled)
        }
    }

    // MARK: - Smoothing Preset

    private enum SmoothingPreset {
        case snappy, smooth, floaty
    }

    private var smoothingPresetBinding: Binding<SmoothingPreset> {
        Binding(
            get: {
                let config = coordinator.project.cursorSmoothing
                if config.stiffness == 400 { return .snappy }
                if config.stiffness == 50 { return .floaty }
                return .smooth
            },
            set: { preset in
                switch preset {
                case .snappy: coordinator.project.cursorSmoothing = .snappy
                case .smooth: coordinator.project.cursorSmoothing = .smooth
                case .floaty: coordinator.project.cursorSmoothing = .floaty
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
