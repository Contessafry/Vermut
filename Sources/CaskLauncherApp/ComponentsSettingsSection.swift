import SwiftUI
import CaskLauncherCore

/// Settings › Components: DXMT, DXVK placeholder, D3DMetal.
struct ComponentsSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s8) {
            DXMTVersionsSettingsSection()
            DXVKComponentsPlaceholder()
            D3DMetalSettingsSection()
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

private struct DXVKComponentsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text("DXVK")
                .font(VermutType.headline)
            Text("Same manager, same structure (currently only one version: v1.10.3 async).")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
        }
    }
}

struct DXMTVersionsSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = DXMTVersionsViewModel()
    @State private var pendingRemove: DXMTReleaseInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text("DXMT")
                .font(VermutType.headline)
            Text("Translates DirectX 10/11 to Metal. Vermut uses the default version, unless a bottle or game chooses another. Only stable GitHub releases are listed — nightly DXMT builds are never offered.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let suggestion = model.updateSuggestion {
                HStack(alignment: .center, spacing: VermutSpace.s3) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.Vermut.info)
                    Text("DXMT \(suggestion.tag) is available.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.infoSubtleForeground)
                    Spacer(minLength: VermutSpace.s2)
                    Button("Install and set as default") {
                        model.acceptUpdateSuggestion()
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                }
                .padding(VermutSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Vermut.infoSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                        .strokeBorder(Color.Vermut.infoBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(model.releases) { release in
                    releaseRow(release)
                    if release.id != model.releases.last?.id {
                        Rectangle().fill(Color.Vermut.border).frame(height: 1)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))

            HStack {
                Text(model.footerText)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(2)
                Spacer(minLength: VermutSpace.s2)
                Button("Check for updates") {
                    Task { await model.refreshFromNetwork() }
                }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                .disabled(model.isLoading)
            }
        }
        .task {
            await model.refreshFromNetwork()
        }
        .onChange(of: appState.configuration.defaultDXMTVersion) { _, _ in
            model.refreshLocal()
        }
        .confirmationDialog(
            pendingRemove.map { "Remove DXMT \($0.tag)?" } ?? "Remove DXMT?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRemove {
                Button("Remove", role: .destructive) {
                    model.uninstall(pendingRemove.tag)
                    self.pendingRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    self.pendingRemove = nil
                }
            }
        } message: {
            Text("Games that used it will fall back to the default (\(appState.configuration.defaultDXMTVersion)).")
        }
    }

    private func releaseRow(_ release: DXMTReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
                Text(titleLine(release))
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                Spacer(minLength: VermutSpace.s2)
                badges(release)
            }

            switch release.rowState {
            case .downloading(let progress, _, _):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Spacer()
                    Button("Cancel") { model.cancelDownload() }
                        .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                }
            case .installing:
                ProgressView()
                    .controlSize(.small)
                Text("Installing…")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            case .failed(let message):
                Text(message)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.errorSubtleForeground)
                Button("Retry") { model.install(release.tag) }
                    .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
            default:
                actions(release)
            }
        }
        .padding(VermutSpace.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(release))
    }

    private func titleLine(_ release: DXMTReleaseInfo) -> String {
        var parts = [release.tag]
        if release.isLatest {
            parts.append("latest")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func badges(_ release: DXMTReleaseInfo) -> some View {
        HStack(spacing: VermutSpace.s1) {
            if release.isDefault {
                VermutBadge(kind: .success, text: "Default", showsDot: true)
            } else if release.isInstalled {
                VermutBadge(kind: .neutral, text: "Installed")
            }
            if let inUse = release.inUseLabel {
                VermutBadge(kind: .neutral, text: inUse)
            }
            if case .failed = release.rowState {
                VermutBadge(kind: .error, text: "Download failed")
            }
        }
    }

    @ViewBuilder
    private func actions(_ release: DXMTReleaseInfo) -> some View {
        HStack(spacing: VermutSpace.s2) {
            if let notes = release.releaseNotesURL {
                Link("Release notes", destination: notes)
                    .font(VermutType.callout)
            }
            Spacer(minLength: VermutSpace.s2)
            if release.isInstalled {
                if !release.isDefault {
                    Button("Set as default") {
                        model.setAsDefault(release.tag)
                        appState.configuration.defaultDXMTVersion = release.tag
                        appState.saveConfiguration()
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                }
                Button("Remove…") {
                    pendingRemove = release
                }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                .disabled(release.isDefault)
                .help(release.isDefault ? "Set another version as default first." : "Remove this DXMT build")
            } else {
                Button("Install") {
                    model.install(release.tag)
                }
                .buttonStyle(VermutButtonStyle(kind: .primary, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
            }
        }
    }

    private func accessibilityLabel(_ release: DXMTReleaseInfo) -> String {
        var parts = ["DXMT \(release.tag)"]
        if release.isDefault { parts.append("default") }
        else if release.isInstalled { parts.append("installed") }
        if let inUse = release.inUseLabel { parts.append(inUse) }
        return parts.joined(separator: ", ")
    }
}
