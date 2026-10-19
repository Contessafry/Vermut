import SwiftUI
import CaskLauncherCore

struct DownloadsView: View {
    @EnvironmentObject var appState: AppState

    private var rows: [GameStore] {
        GameStore.allCases.filter { store in
            switch appState.status(for: store) {
            case .downloading, .installing, .error:
                return true
            default:
                return false
            }
        }
    }

    private var gameRows: [GameDownload] {
        appState.gameDownloads.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VermutSpace.s6) {
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text("Downloads")
                        .font(VermutType.title)
                        .foregroundStyle(Color.Vermut.foreground)
                    Text("Store setup and Epic game downloads.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                }

                if rows.isEmpty && gameRows.isEmpty {
                    if appState.allStoresInstalled {
                        VermutEmptyState(
                            systemImage: "arrow.down.circle",
                            title: "No downloads in progress",
                            message: "Open the library to install an Epic game, or launch Steam and GOG from Stores.",
                            actionTitle: "Open Library",
                            action: { appState.section = .library }
                        )
                    } else {
                        VermutEmptyState(
                            systemImage: "arrow.down.circle",
                            title: "No downloads in progress",
                            message: "When you install Steam, sign in to Epic, or install GOG, progress shows up here.",
                            actionTitle: "Open Stores",
                            action: { appState.section = .stores }
                        )
                    }
                } else {
                    VStack(spacing: VermutSpace.s3) {
                        ForEach(rows) { store in
                            downloadRow(store)
                        }
                        ForEach(gameRows) { download in
                            gameDownloadRow(download)
                        }
                    }
                }
            }
            .padding(VermutSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.Vermut.background)
    }

    private func downloadRow(_ store: GameStore) -> some View {
        let status = appState.status(for: store)
        let presentation = StoreStatusPresentation.from(status)
        return HStack(alignment: .top, spacing: VermutSpace.s3) {
            StoreLogoTile(store: store, size: 32)
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
                    Text(store.rawValue)
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.foreground)
                        .lineLimit(1)
                    Spacer(minLength: VermutSpace.s2)
                    VermutBadge(
                        kind: presentation.kind,
                        text: presentation.text,
                        systemImage: presentation.symbol,
                        showsDot: presentation.showsDot
                    )
                    .fixedSize()
                }
                if case .downloading = status {
                    StoreInstallControls(store: store, status: status)
                    Text(store.installerFilename)
                        .font(VermutType.mono)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineLimit(2)
                } else if case .installing = status {
                    StoreInstallControls(store: store, status: status)
                } else if case .error(let message) = status {
                    Text(message)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.errorSubtleForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.installingCopy)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .error = status {
                    HStack(spacing: VermutSpace.s2) {
                        Button("Retry") { appState.retryStore(store) }
                            .buttonStyle(
                                VermutButtonStyle(
                                    kind: .outline,
                                    height: VermutHeight.buttonSmall,
                                    radius: VermutRadius.xsPlus,
                                    font: VermutType.callout,
                                    horizontalPadding: VermutSpace.s2
                                )
                            )
                        Button("View logs") { appState.openLogs(for: store) }
                            .buttonStyle(
                                VermutButtonStyle(
                                    kind: .ghost,
                                    height: VermutHeight.buttonSmall,
                                    radius: VermutRadius.xsPlus,
                                    font: VermutType.callout,
                                    horizontalPadding: VermutSpace.s2
                                )
                            )
                    }
                }
            }
        }
        .vermutCard()
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func gameDownloadRow(_ download: GameDownload) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s3) {
            StoreLogoTile(store: download.store, size: 32)
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
                    Text(download.name)
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.foreground)
                        .lineLimit(1)
                    Spacer(minLength: VermutSpace.s2)
                    if download.isFailed {
                        VermutBadge(kind: .error, text: "Failed", systemImage: "exclamationmark.circle", showsDot: false)
                            .fixedSize()
                    } else {
                        VermutBadge(
                            kind: .info,
                            text: "Downloading · \(Int(min(max(download.progress, 0), 0.99) * 100))%",
                            systemImage: "arrow.down.circle",
                            showsDot: false
                        )
                        .fixedSize()
                    }
                }
                if download.isFailed {
                    Text(download.error ?? "Download failed")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.errorSubtleForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VermutProgressBar(value: download.progress)
                    if !download.detail.isEmpty {
                        Text(download.detail)
                            .font(VermutType.mono)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineLimit(2)
                    }
                    Button("Cancel") { appState.cancelEpicGameDownload(download) }
                        .buttonStyle(
                            VermutButtonStyle(
                                kind: .ghost,
                                height: VermutHeight.buttonSmall,
                                radius: VermutRadius.xsPlus,
                                font: VermutType.callout,
                                horizontalPadding: VermutSpace.s2
                            )
                        )
                }
            }
        }
        .vermutCard()
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
