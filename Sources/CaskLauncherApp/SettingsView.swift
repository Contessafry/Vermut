import SwiftUI
import CaskLauncherCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case wineEngines
    case components
    case maintenance
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .wineEngines: return "Wine Engines"
        case .components: return "Components"
        case .maintenance: return "Maintenance"
        case .info: return "Info"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmReset: GameStore?

    private var tab: Binding<SettingsTab> {
        Binding(
            get: { appState.settingsTab },
            set: { appState.settingsTab = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(VermutType.title)
                .foregroundStyle(Color.Vermut.foreground)
                .padding(.horizontal, VermutSpace.s6)
                .padding(.top, VermutSpace.s6)
                .padding(.bottom, VermutSpace.s3)

            tabBar
                .padding(.horizontal, VermutSpace.s6)

            ScrollView {
                Group {
                    switch tab.wrappedValue {
                    case .general:
                        generalPane
                    case .wineEngines:
                        WineEnginesSettingsSection()
                    case .components:
                        ComponentsSettingsSection()
                    case .maintenance:
                        maintenancePane
                    case .info:
                        infoPane
                    }
                }
                .padding(VermutSpace.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Vermut.background)
        .sheet(item: $confirmReset) { store in
            DeleteBottleSheet(store: store) {
                confirmReset = nil
                appState.resetStore(store)
            } onCancel: {
                confirmReset = nil
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VermutSpace.s6) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        appState.settingsTab = item
                    } label: {
                        VStack(spacing: VermutSpace.s2) {
                            Text(item.title)
                                .font(VermutType.bodyEmphasis)
                                .foregroundStyle(appState.settingsTab == item ? Color.Vermut.foreground : Color.Vermut.mutedForeground)
                                .lineLimit(1)
                            Rectangle()
                                .fill(appState.settingsTab == item ? Color.Vermut.foreground : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(VermutMotion.selection, value: appState.settingsTab)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.Vermut.border).frame(height: 1)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s8) {
            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                Text("Defaults for new bottles. Existing bottles keep Automatic unless you override them.")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Default settings")
                    .font(VermutType.headline)
                    .padding(.bottom, VermutSpace.s3)

                settingsRow("Wine engine", help: "Used when a bottle is set to Automatic") {
                    Picker("", selection: $appState.configuration.defaultEngine) {
                        ForEach(WineEngine.allCases) { engine in
                            Text(engine.userFacingName).tag(engine.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 220, minHeight: VermutHeight.field)
                }

                settingsRow("Graphics backend", help: "DXMT needs Vermut Wine") {
                    Picker("", selection: $appState.configuration.defaultGraphicsBackend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.shortLabel).tag(backend.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160, minHeight: VermutHeight.field)
                }

                settingsRow("Default DXMT", help: "Global default; bottles/games may override") {
                    Text(appState.configuration.defaultDXMTVersion)
                        .font(VermutType.mono)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                }

                settingsRow(
                    "Update channel",
                    help: "Stable uses GitHub releases only. Beta also offers pre-releases. Switching back to Stable never suggests a downgrade."
                ) {
                    Picker("", selection: $appState.configuration.updateChannel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.userFacingName).tag(channel.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 140, minHeight: VermutHeight.field)
                }

                settingsRow("Retina mode", help: "New bottles render at native resolution") {
                    Toggle("", isOn: $appState.configuration.enableHiDPI)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Color.Vermut.primary)
                }

                settingsRow("Windows version", help: "Reported to games in new bottles") {
                    Picker("", selection: $appState.configuration.windowsVersion) {
                        Text("Windows 10").tag("win10")
                        Text("Windows 8.1").tag("win81")
                        Text("Windows 7").tag("win7")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160, minHeight: VermutHeight.field)
                }
            }
            .onChange(of: appState.configuration.defaultEngine) { _, _ in appState.saveConfiguration() }
            .onChange(of: appState.configuration.defaultGraphicsBackend) { _, _ in appState.saveConfiguration() }
            .onChange(of: appState.configuration.updateChannel) { _, _ in
                appState.saveConfiguration()
                UpdateChecker.shared.clearDismissed()
                appState.availableUpdate = nil
                Task { await appState.checkForUpdateManually() }
            }
            .onChange(of: appState.configuration.enableHiDPI) { _, _ in appState.saveConfiguration() }
            .onChange(of: appState.configuration.windowsVersion) { _, _ in appState.saveConfiguration() }
            .frame(maxWidth: 640, alignment: .leading)

            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                Text("Compatibility reports")
                    .font(VermutType.headline)
                Text("After playing a game for 5+ minutes, Vermut can prompt you to share how well it ran via a GitHub issue (filled out for you).")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Show compatibility prompts", isOn: Binding(
                    get: { CompatibilityService.shared.isPromptEnabled },
                    set: { CompatibilityService.shared.isPromptEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .tint(.accentColor)
            }
        }
    }

    private var maintenancePane: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text("Maintenance")
                .font(VermutType.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s2) {
                    Button("Open bottles folder") { appState.openBottlesFolder() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                    Button("Copy diagnostic report") { appState.copyDiagnosticReport() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                }
                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    Button("Open bottles folder") { appState.openBottlesFolder() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                    Button("Copy diagnostic report") { appState.copyDiagnosticReport() }
                        .buttonStyle(VermutButtonStyle(kind: .outline))
                }
            }
            Text("Resetting a bottle deletes its prefix. Store accounts and cloud saves are not stored here.")
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
            ForEach(GameStore.allCases) { store in
                HStack(spacing: VermutSpace.s2) {
                    StoreLogoTile(store: store, size: 16)
                    Text(store.rawValue)
                        .font(VermutType.body)
                        .lineLimit(1)
                    Spacer(minLength: VermutSpace.s2)
                    Menu {
                        Button("Reset bottle", role: .destructive) {
                            confirmReset = store
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("\(store.shortName) maintenance")
                }
                .padding(.vertical, VermutSpace.s2)
                .frame(minHeight: VermutHeight.formRow)
            }
        }
    }

    private var infoPane: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text("About")
                .font(VermutType.headline)
            Text("Pour. Click. Play.")
                .font(VermutType.bodyEmphasis)
                .foregroundStyle(Color.Vermut.foreground)
            HStack(spacing: VermutSpace.s2) {
                Text("Vermut \(appState.appVersion) · Free and open source")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                if SemVer.tagIsPrerelease(VermutProject.version) {
                    VermutBadge(kind: .info, text: "Beta")
                }
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            Text("Epic Games uses Legendary (\(LegendaryCLI.licenceName)), a free Epic store client by derrod. Vermut runs it as a separate process.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("DXMT from v0.80 is LGPL 2.1+ (3Shain/dxmt). Wine engines are LGPL 2.1+.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: VermutSpace.s4) {
                Link("GitHub", destination: VermutProject.githubURL)
                Link("Licence", destination: VermutProject.licenseURL)
                Link("Legendary", destination: LegendaryCLI.sourceURL)
                Link("Third-party", destination: URL(string: "https://github.com/Contessafry/Vermut/blob/main/THIRD_PARTY.md")!)
            }
            .font(VermutType.bodyEmphasis)
            .foregroundStyle(Color.Vermut.foreground)
        }
    }

    private func settingsRow<Content: View>(_ title: String, help: String, @ViewBuilder control: () -> Content) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.Vermut.border).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: VermutSpace.s6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(VermutType.bodyEmphasis)
                        Text(help)
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: VermutSpace.s3)
                    control()
                }
                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(VermutType.bodyEmphasis)
                        Text(help)
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    control()
                }
            }
            .padding(.vertical, VermutSpace.s3)
            .frame(minHeight: VermutHeight.formRow, alignment: .leading)
        }
    }
}
