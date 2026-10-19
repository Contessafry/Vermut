import SwiftUI
import CaskLauncherCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmReset: GameStore?

    private static let githubURL = VermutProject.githubURL
    private static let licenceURL = VermutProject.licenseURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VermutSpace.s8) {
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text("Settings")
                        .font(VermutType.title)
                        .foregroundStyle(Color.Vermut.foreground)
                    Text("Defaults for new bottles. Existing bottles keep the values saved on their General tab.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Default settings")
                        .font(VermutType.headline)
                        .padding(.bottom, VermutSpace.s3)

                    settingsRow("Wine engine", help: "Used when installing a new store") {
                        Picker("", selection: $appState.configuration.defaultEngine) {
                            ForEach(WineEngine.allCases) { engine in
                                Text(engine.userFacingName).tag(engine.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 220, minHeight: VermutHeight.field)
                    }

                    settingsRow("Graphics backend", help: "DXMT needs Vermut Wine 11") {
                        Picker("", selection: $appState.configuration.defaultGraphicsBackend) {
                            ForEach(GraphicsBackend.allCases) { backend in
                                Text(backend.shortLabel).tag(backend.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 160, minHeight: VermutHeight.field)
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
                .onChange(of: appState.configuration.enableHiDPI) { _, _ in appState.saveConfiguration() }
                .onChange(of: appState.configuration.windowsVersion) { _, _ in appState.saveConfiguration() }
                .frame(maxWidth: 640, alignment: .leading)

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

                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    Text("About")
                        .font(VermutType.headline)
                    Text("Pour. Click. Play.")
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.foreground)
                    Text("Vermut \(appState.appVersion) · Free and open source")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Epic Games uses Legendary (\(LegendaryCLI.licenceName)), a free Epic store client by derrod. Vermut runs it as a separate process.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: VermutSpace.s4) {
                        Link("GitHub", destination: Self.githubURL)
                        Link("Licence", destination: Self.licenceURL)
                        Link("Legendary", destination: LegendaryCLI.sourceURL)
                    }
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                }
            }
            .padding(VermutSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
