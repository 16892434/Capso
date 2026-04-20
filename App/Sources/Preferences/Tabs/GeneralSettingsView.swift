// App/Sources/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI
import LaunchAtLogin
import AppKit

struct GeneralSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(title: "Startup") {
                SettingCard {
                    SettingRow(label: "Launch at Login", sublabel: "Start Capso when you log in") {
                        LaunchAtLogin.Toggle { Text("") }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    // TODO: Re-enable "Show Menu Bar Icon" once MenuBarController
                    // actually respects AppSettings.showMenuBarIcon. Today it
                    // unconditionally installs the status item in
                    // setupStatusItem(), so this toggle did nothing when flipped.
                    // Uncomment the SettingRow below when the feature is wired.
                    // SettingRow(label: "Show Menu Bar Icon", showDivider: true) {
                    //     Toggle("", isOn: $viewModel.showMenuBarIcon)
                    //         .toggleStyle(.switch)
                    //         .controlSize(.small)
                    // }
                }
            }

            SettingGroup(title: "Sound") {
                SettingCard {
                    SettingRow(label: "Shutter Sound", sublabel: "Play sound after capture") {
                        Toggle("", isOn: $viewModel.playShutterSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if let updateManager {
                SettingGroup(title: "Updates") {
                    SettingCard {
                        SettingRow(label: "Check for Updates", sublabel: "Automatically checks daily") {
                            CheckForUpdatesView(updateManager: updateManager)
                        }
                    }
                }
            }

            SettingGroup(title: "History") {
                SettingCard {
                    SettingRow(label: "Save to History", sublabel: "Automatically save all captures") {
                        Toggle("", isOn: $viewModel.historyEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Keep History", sublabel: "Auto-delete older captures", showDivider: true) {
                        Picker("", selection: $viewModel.historyRetention) {
                            Text("1 Week").tag("oneWeek")
                            Text("2 Weeks").tag("twoWeeks")
                            Text("1 Month").tag("oneMonth")
                            Text("Unlimited").tag("unlimited")
                        }
                        .frame(width: 130)
                    }
                }
            }

            SettingGroup(title: "About") {
                SettingCard {
                    SettingRow(label: "Version") {
                        Text(viewModel.appVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                    SettingRow(label: "Report a Bug", sublabel: "Found something broken?", showDivider: true) {
                        ExternalLinkButton(title: "Report", icon: "ladybug") {
                            openURL("https://github.com/lzhgus/Capso/issues/new?template=bug_report.yml&labels=bug")
                        }
                    }
                    SettingRow(label: "Request a Feature", sublabel: "Have an idea?", showDivider: true) {
                        ExternalLinkButton(title: "Request", icon: "lightbulb") {
                            openURL("https://github.com/lzhgus/Capso/issues/new?template=feature_request.yml&labels=enhancement")
                        }
                    }
                    SettingRow(label: "Source Code", sublabel: "View on GitHub", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "chevron.left.forwardslash.chevron.right") {
                            openURL("https://github.com/lzhgus/Capso")
                        }
                    }
                }
            }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ExternalLinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 12))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
    }
}
