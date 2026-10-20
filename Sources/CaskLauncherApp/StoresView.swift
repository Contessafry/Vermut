import SwiftUI
import Darwin
import CaskLauncherCore

struct StoresView: View {
    @EnvironmentObject var appState: AppState
    @State private var contentWidth: CGFloat = 800

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VermutSpace.s6) {
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text("Stores")
                        .font(VermutType.title)
                        .foregroundStyle(Color.Vermut.foreground)
                    Text("Each store runs in its own bottle, isolated and ready to play.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if visibleStores.isEmpty {
                    VermutEmptyState(
                        systemImage: "storefront",
                        title: "No stores match this search",
                        message: "Clear the search field to see Steam, Epic and GOG."
                    )
                } else {
                    storeGrid
                }

                if contentWidth >= 800 {
                    HStack(alignment: .top, spacing: VermutSpace.s4) {
                        ActivityCard()
                            .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                        ThisMacCard()
                            .frame(width: VermutHeight.thisMac)
                    }
                } else {
                    VStack(alignment: .leading, spacing: VermutSpace.s4) {
                        ActivityCard()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ThisMacCard()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(VermutSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .measuringContentWidth($contentWidth)
        }
        .background(Color.Vermut.background)
        .onAppear { appState.refreshBottleMetrics() }
    }

    private var visibleStores: [GameStore] {
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(GameStore.allCases) }
        return GameStore.allCases.filter {
            $0.rawValue.lowercased().contains(query) || $0.identifier.contains(query)
        }
    }

    private var storeGrid: some View {
        let columns: [GridItem]
        if contentWidth >= 692 {
            columns = Array(
                repeating: GridItem(.flexible(), spacing: VermutSpace.s4),
                count: 3
            )
        } else {
            columns = [GridItem(.adaptive(minimum: 260), spacing: VermutSpace.s4)]
        }
        return LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: VermutSpace.s4
        ) {
            ForEach(visibleStores) { store in
                StoreCard(store: store)
            }
        }
    }
}

struct StoreCard: View {
    let store: GameStore
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var status: StoreStatus { appState.status(for: store) }
    var presentation: StoreStatusPresentation {
        .from(status, store: store, epicAccount: appState.epicAccount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            HStack(alignment: .top, spacing: VermutSpace.s3) {
                StoreLogoTile(store: store, size: 40)
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text(store.rawValue)
                        .font(VermutType.headline)
                        .foregroundStyle(Color.Vermut.cardForeground)
                        .lineLimit(1)
                    VermutBadge(
                        kind: presentation.kind,
                        text: presentation.text,
                        systemImage: presentation.symbol,
                        showsDot: presentation.showsDot
                    )
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Open bottle") { appState.section = .bottle(store) }
                    Button("Show C: drive") { appState.openCDrive(for: store) }
                    Button("View logs") { appState.openLogs(for: store) }
                    Divider()
                    Button("Reset bottle", role: .destructive) {
                        appState.bottleToDelete = store
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
                .contentShape(Rectangle())
                .accessibilityLabel("Store actions")
                .help("Store actions")
            }

            Text(descriptionCopy)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if status.isInstallInProgress {
                StoreInstallControls(store: store, status: status)
                    .animation(reduceMotion ? nil : VermutMotion.progress, value: progressValue)
            }

            Rectangle()
                .fill(Color.Vermut.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                Text(BottleLabels.engineLine(bottleConfig))
                Text(BottleLabels.graphicsLine(bottleConfig, store: store))
                Text(sizeLine)
                    .monospacedDigit()
            }
            .font(VermutType.mono)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .vermutCard()
        .frame(minWidth: 220, minHeight: 220, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var descriptionCopy: String {
        switch status {
        case .downloading, .installing:
            return store.installingCopy
        case .error(let message):
            return message
        default:
            if store == .epic, appState.epicAccount != nil {
                return EpicStoreCopy.signedInDescription
            }
            return store.blurb
        }
    }

    private var bottleConfig: BottleConfiguration {
        StoreRecipe.normalized(appState.loadBottle(store), for: store)
    }

    private var sizeLine: String {
        let size = appState.bottleSizes[store] ?? 0
        let sizeText = size > 0 ? ByteFormat.string(size) : "—"
        return "bottle/\(store.identifier)  ·  \(sizeText)"
    }

    private var progressValue: Double {
        if case .downloading(let progress) = status { return progress }
        return 0
    }

    @ViewBuilder
    private var actions: some View {
        if store == .epic {
            epicActions
        } else {
            storeActions
        }
    }

    @ViewBuilder
    private var epicActions: some View {
        switch status {
        case .notInstalled:
            Button("Sign in") { appState.signInEpic() }
                .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
        case .downloading, .installing:
            EmptyView()
        case .installed, .running:
            if let account = appState.epicAccount {
                VStack(spacing: VermutSpace.s2) {
                    Button("Open library") { appState.openEpicLibraryOrSignIn() }
                        .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
                    HStack(spacing: VermutSpace.s2) {
                        Text(account.displayName)
                            .font(VermutType.captionRegular)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Log out") { appState.logoutEpic() }
                            .buttonStyle(VermutButtonStyle(kind: .ghost, fillWidth: false))
                            .fixedSize()
                    }
                }
            } else {
                Button("Sign in") { appState.signInEpic() }
                    .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
            }
        case .error:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s2) {
                    Button("Retry") { appState.signInEpic() }
                        .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                    Button("View logs") { appState.openLogs(for: store) }
                        .buttonStyle(VermutButtonStyle(kind: .ghost))
                        .fixedSize()
                }
                VStack(spacing: VermutSpace.s2) {
                    Button("Retry") { appState.signInEpic() }
                        .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                    Button("View logs") { appState.openLogs(for: store) }
                        .buttonStyle(VermutButtonStyle(kind: .ghost, fillWidth: true))
                }
            }
        }
    }

    @ViewBuilder
    private var storeActions: some View {
        if StoreRecipe.isComingSoon(store) {
            Button("Coming soon") {}
                .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                .disabled(true)
                .help("GOG Galaxy support is coming in a future update.")
        } else {
        switch status {
        case .notInstalled:
            Button("Install") { appState.installStore(store) }
                .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
        case .downloading, .installing:
            EmptyView()
        case .installed:
            Button(store.openTitle) { appState.launchStore(store) }
                .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
        case .running:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s2) {
                    Button(store.openTitle) { appState.launchStore(store) }
                        .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
                    Button {
                        appState.stopStore(store)
                    } label: {
                        Label("Quit", systemImage: "stop.circle")
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                    .help("Stop this store")
                    .fixedSize()
                }
                VStack(spacing: VermutSpace.s2) {
                    Button(store.openTitle) { appState.launchStore(store) }
                        .buttonStyle(VermutButtonStyle(kind: .primary, fillWidth: true))
                    Button {
                        appState.stopStore(store)
                    } label: {
                        Label("Quit", systemImage: "stop.circle")
                    }
                    .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                    .help("Stop this store")
                }
            }
        case .error:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s2) {
                    Button("Retry") { appState.retryStore(store) }
                        .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                    Button("View logs") { appState.openLogs(for: store) }
                        .buttonStyle(VermutButtonStyle(kind: .ghost))
                        .fixedSize()
                }
                VStack(spacing: VermutSpace.s2) {
                    Button("Retry") { appState.retryStore(store) }
                        .buttonStyle(VermutButtonStyle(kind: .outline, fillWidth: true))
                    Button("View logs") { appState.openLogs(for: store) }
                        .buttonStyle(VermutButtonStyle(kind: .ghost, fillWidth: true))
                }
            }
        }
        }
    }
}

struct ActivityCard: View {
    @EnvironmentObject var appState: AppState

    private var items: [ActivityItem] {
        GameStore.allCases.compactMap { store in
            switch appState.status(for: store) {
            case .running:
                return ActivityItem(
                    id: store.identifier + "-run",
                    kind: .success,
                    symbol: "checkmark.circle",
                    title: "\(store.shortName) started",
                    detail: "Launched with \(BottleLabels.engineName(appState.loadBottle(store)))",
                    time: "now",
                    actionTitle: nil,
                    action: nil
                )
            case .downloading(let progress):
                let percent = Int(min(max(progress, 0), 0.99) * 100)
                return ActivityItem(
                    id: store.identifier + "-dl",
                    kind: .info,
                    symbol: "arrow.down.circle",
                    title: "Downloading \(store.rawValue)",
                    detail: store.installerFilename,
                    time: "\(percent)%",
                    actionTitle: "Cancel",
                    action: { appState.cancelInstall(store) }
                )
            case .installing(.settingUp):
                return ActivityItem(
                    id: store.identifier + "-in",
                    kind: .info,
                    symbol: "arrow.down.circle",
                    title: "Setting up \(store.rawValue)",
                    detail: "Download complete. Setting up…",
                    time: "now",
                    actionTitle: "Cancel",
                    action: { appState.cancelInstall(store) }
                )
            case .installing(.updatingClient):
                return ActivityItem(
                    id: store.identifier + "-upd",
                    kind: .info,
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Updating \(store.rawValue)",
                    detail: "First-run update. \(store.rawValue) will be ready in a few minutes.",
                    time: "now",
                    actionTitle: "Cancel",
                    action: { appState.cancelInstall(store) }
                )
            case .installing(.awaitingWindow):
                return ActivityItem(
                    id: store.identifier + "-wiz",
                    kind: .warning,
                    symbol: "exclamationmark.triangle",
                    title: "Finish the installer window",
                    detail: "\(store.rawValue) is waiting on the setup wizard.",
                    time: "now",
                    actionTitle: "Bring to front",
                    action: { appState.bringInstallerToFront(store) },
                    secondaryTitle: "Cancel",
                    secondaryAction: { appState.cancelInstall(store) }
                )
            case .error(let message):
                return ActivityItem(
                    id: store.identifier + "-err",
                    kind: .error,
                    symbol: "exclamationmark.circle",
                    title: "\(store.shortName) failed",
                    detail: message,
                    time: "now",
                    actionTitle: "Retry",
                    action: { appState.retryStore(store) }
                )
            default:
                return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            HStack {
                Text("Activity")
                    .font(VermutType.headline)
                    .foregroundStyle(Color.Vermut.cardForeground)
                Spacer()
                Button {
                    if let store = GameStore.allCases.first(where: {
                        if case .error = appState.status(for: $0) { return true }
                        return false
                    }) {
                        appState.openLogs(for: store)
                    } else {
                        appState.copyDiagnosticReport()
                    }
                } label: {
                    HStack(spacing: VermutSpace.s1) {
                        Text("View logs")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(VermutButtonStyle(kind: .ghost, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                .help("Copy diagnostic report or open bottle logs")
            }

            if items.isEmpty {
                VStack(alignment: .leading, spacing: VermutSpace.s3) {
                    Text(
                        appState.hasAnyInstalledStore
                            ? "No recent activity. Open a store to start playing."
                            : "Nothing running yet. Install a store to get started."
                    )
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    if !appState.hasAnyInstalledStore {
                        Button("Install a store") {
                            appState.section = .stores
                        }
                        .buttonStyle(VermutButtonStyle(kind: .primary))
                    }
                }
                .padding(.vertical, VermutSpace.s4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(Color.Vermut.border).frame(height: 1)
                        }
                        activityRow(item)
                    }
                }
            }
        }
        .vermutCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityRow(_ item: ActivityItem) -> some View {
        HStack(alignment: .top, spacing: VermutSpace.s3) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(item.kind.solid)
                .frame(width: 16, height: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
                    Text(item.title)
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.cardForeground)
                        .lineLimit(2)
                    Spacer(minLength: VermutSpace.s2)
                    Text(item.time)
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(item.detail)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let title = item.actionTitle, let action = item.action {
                    HStack(spacing: VermutSpace.s2) {
                        Button(title, action: action)
                            .buttonStyle(
                                VermutButtonStyle(
                                    kind: item.kind == .warning ? .primary : .outline,
                                    height: VermutHeight.buttonSmall,
                                    radius: VermutRadius.xsPlus,
                                    font: VermutType.callout,
                                    horizontalPadding: VermutSpace.s2
                                )
                            )
                        if let secondaryTitle = item.secondaryTitle, let secondary = item.secondaryAction {
                            Button(secondaryTitle, action: secondary)
                                .buttonStyle(
                                    VermutButtonStyle(
                                        kind: .outline,
                                        height: VermutHeight.buttonSmall,
                                        radius: VermutRadius.xsPlus,
                                        font: VermutType.callout,
                                        horizontalPadding: VermutSpace.s2
                                    )
                                )
                        }
                    }
                    .padding(.top, VermutSpace.s1)
                }
            }
        }
        .padding(.vertical, VermutSpace.s3)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityItem: Identifiable {
    var id: String
    var kind: VermutStatusKind
    var symbol: String
    var title: String
    var detail: String
    var time: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
}

struct ThisMacCard: View {
    @EnvironmentObject var appState: AppState

    private var totalBottleBytes: Int64 {
        appState.bottleSizes.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            Text("This Mac")
                .font(VermutType.headline)
                .foregroundStyle(Color.Vermut.cardForeground)

            infoRow(systemImage: "cpu", title: HostInfo.chipName, badge: ("Supported", .success))
            infoRow(
                systemImage: "gearshape.2",
                title: "Rosetta 2",
                badge: appState.hasRosetta ? ("Installed", .success) : ("Missing", .warning)
            )
            infoRow(
                systemImage: "display",
                title: "Graphics",
                trailing: HostInfo.graphicsSummary(hasD3DMetal: appState.hasD3DMetal)
            )

            Text("Storage used by bottles")
                .font(VermutType.bodyEmphasis)
                .foregroundStyle(Color.Vermut.cardForeground)
                .padding(.top, VermutSpace.s2)

            storageBar

            ViewThatFits(in: .horizontal) {
                HStack(spacing: VermutSpace.s4) {
                    legend(Color.Vermut.Neutral.s700, "Steam")
                    legend(Color.Vermut.Neutral.s500, "Epic")
                    legend(Color.Vermut.Neutral.s400, "GOG")
                }
                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    legend(Color.Vermut.Neutral.s700, "Steam")
                    legend(Color.Vermut.Neutral.s500, "Epic")
                    legend(Color.Vermut.Neutral.s400, "GOG")
                }
            }
            .font(VermutType.captionRegular)
        }
        .vermutCard()
        .frame(minWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow(systemImage: String, title: String, badge: (String, VermutStatusKind)? = nil, trailing: String? = nil) -> some View {
        HStack(spacing: VermutSpace.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.Vermut.mutedForeground)
                .frame(width: 16, height: 16)
            Text(title)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.cardForeground)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: VermutSpace.s2)
            if let badge {
                VermutBadge(kind: badge.1, text: badge.0, showsDot: false)
                    .fixedSize()
            }
            if let trailing {
                Text(trailing)
                    .font(VermutType.mono)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(minHeight: VermutHeight.sidebarRow)
    }

    private var storageBar: some View {
        let volume = HostInfo.volumeCapacity()
        let steam = Double(appState.bottleSizes[.steam] ?? 0)
        let epic = Double(appState.bottleSizes[.epic] ?? 0)
        let gog = Double(appState.bottleSizes[.gog] ?? 0)
        let used = steam + epic + gog
        let cap = max(Double(volume.total), 1)

        return VStack(alignment: .leading, spacing: VermutSpace.s2) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 1) {
                    Rectangle().fill(Color.Vermut.Neutral.s700).frame(width: max(0, w * steam / cap))
                    Rectangle().fill(Color.Vermut.Neutral.s500).frame(width: max(0, w * epic / cap))
                    Rectangle().fill(Color.Vermut.Neutral.s400).frame(width: max(0, w * gog / cap))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: VermutHeight.progress)
            .background(Color.Vermut.muted)
            .clipShape(Capsule())

            Text("\(ByteFormat.string(Int64(used))) / \(ByteFormat.string(volume.total))")
                .font(VermutType.mono)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .monospacedDigit()
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: VermutSpace.s1) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(Color.Vermut.mutedForeground)
        }
    }
}

enum HostInfo {
    static var chipName: String {
        #if arch(arm64)
        if let brand = sysctl("machdep.cpu.brand_string"), !brand.isEmpty {
            return brand
        }
        return "Apple Silicon"
        #else
        return sysctl("machdep.cpu.brand_string") ?? "This Mac"
        #endif
    }

    static func graphicsSummary(hasD3DMetal: Bool) -> String {
        hasD3DMetal ? "Metal · D3DMetal" : "Metal · DXMT"
    }

    static func volumeCapacity() -> (total: Int64, free: Int64) {
        let url = PathManager.shared.appSupportURL
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        return (total, free)
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
