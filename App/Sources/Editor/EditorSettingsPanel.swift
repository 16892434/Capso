import SwiftUI
import EditorKit
import ExportKit
import SharedKit

struct EditorSettingsPanel: View {
    @Bindable var coordinator: EditorCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 4)

                backgroundSection
                zoomSection
                cursorSection
                exportSection
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
                    Divider().background(Color.white.opacity(0.06))

                    settingPickerRow("Type", selection: $coordinator.project.backgroundStyle.colorType) {
                        Text("Solid").tag(BackgroundColorType.solid)
                        Text("Gradient").tag(BackgroundColorType.gradient)
                    }

                    Divider().background(Color.white.opacity(0.06))

                    settingSliderRow(
                        "Padding",
                        value: $coordinator.project.backgroundStyle.padding,
                        range: 0...80,
                        unit: "pt"
                    )

                    settingSliderRow(
                        "Corners",
                        value: $coordinator.project.backgroundStyle.cornerRadius,
                        range: 0...24,
                        unit: "pt"
                    )

                    Divider().background(Color.white.opacity(0.06))

                    settingToggleRow(
                        "Shadow",
                        isOn: $coordinator.project.backgroundStyle.shadowEnabled
                    )

                    if coordinator.project.backgroundStyle.shadowEnabled {
                        settingSliderRow(
                            "Radius",
                            value: $coordinator.project.backgroundStyle.shadowRadius,
                            range: 0...30,
                            unit: "pt"
                        )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.backgroundStyle.enabled)
        }
    }

    // MARK: - Zoom Section

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Zoom")

            settingCard {
                HStack {
                    Text("Segments")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(coordinator.project.zoomSegments.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.06))

                Text("Click on the timeline to add zoom segments. Zoom rendering will be enabled in a future update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
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
                    Divider().background(Color.white.opacity(0.06))

                    HStack {
                        Text("Style")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: smoothingPresetBinding) {
                            Text("Snappy").tag(SmoothingPreset.snappy)
                            Text("Smooth").tag(SmoothingPreset.smooth)
                            Text("Floaty").tag(SmoothingPreset.floaty)
                        }
                        .frame(width: 100)
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: coordinator.project.cursorSmoothing.enabled)
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Export")

            settingCard {
                HStack {
                    Text("Format")
                        .font(.system(size: 13))
                    Spacer()
                    Text("MP4 / GIF")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().background(Color.white.opacity(0.06))

                Text("Export uses the existing pipeline. Compositing effects will be added in a future update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Smoothing Preset Binding

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
                case .snappy:
                    coordinator.project.cursorSmoothing = .snappy
                case .smooth:
                    coordinator.project.cursorSmoothing = .smooth
                case .floaty:
                    coordinator.project.cursorSmoothing = .floaty
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

    private func settingSliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
            .frame(width: 100)
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
