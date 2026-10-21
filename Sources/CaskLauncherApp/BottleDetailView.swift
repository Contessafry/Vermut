import SwiftUI
import CaskLauncherCore

struct BottleDetailView: View {
    let store: GameStore
    @EnvironmentObject var appState: AppState
    @State private var tab: BottleTab = .general
    @State private var config: BottleConfiguration
    @State private var confirmDelete = false
    @State private var pendingEngineAfterDownload: WineEngine?
    @StateObject private var enginesModel = WineEnginesViewModel()

    init(store: GameStore) {
        self.store = store
        _config = State(initialValue: BottleConfiguration())
    }

    private var status: StoreStatus { appState.status(for: store) }
    private var presentation: StoreStatusPresentation {
        .from(status, store: store, epicAccount: appState.epicAccount)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: VermutSpace.s6) {
                    header(width: width)
                    tabBar
                    if width >= 900 {
                        HStack(alignment: .top, spacing: VermutSpace.s4) {
                            tabBody(width: width)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            sideColumn
                                .frame(width: VermutHeight.bottleSide)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: VermutSpace.s6) {
                            tabBody(width: width)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            sideColumn
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(VermutSpace.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.Vermut.background)
        }
        .onAppear {
            config = appState.loadBottle(store)
            appState.refreshBottleMetrics()
        }
        .onChange(of: store) { _, newStore in
            config = appState.loadBottle(newStore)
            tab = .general
        }
        .sheet(isPresented: $confirmDelete) {
            DeleteBottleSheet(store: store) {
                confirmDelete = false
                appState.resetStore(store)
            } onCancel: {
                confirmDelete = false
            }
        }
        .alert(
            enginesModel.pendingDownload.map { enginesModel.confirmSheetTitle(for: $0) } ?? "Download engine?",
            isPresented: Binding(
                get: { enginesModel.pendingDownload != nil },
                set: { if !$0 { enginesModel.cancelPendingDownload() } }
            )
        ) {
            Button("Download") {
                if let engine = enginesModel.pendingDownload {
                    pendingEngineAfterDownload = engine
                }
                // Keep current engine until download finishes (spec: applies on next launch).
                enginesModel.confirmPendingDownload()
            }
            Button("Cancel", role: .cancel) {
                pendingEngineAfterDownload = nil
                enginesModel.cancelPendingDownload()
            }
        } message: {
            if let engine = enginesModel.pendingDownload {
                Text(enginesModel.confirmSheetMessage(for: engine))
            }
        }
        .onAppear { enginesModel.refresh() }
        .onChange(of: enginesModel.busyEngine) { _, busy in
            guard busy == nil, let pending = pendingEngineAfterDownload else { return }
            if EngineManager.shared.isEngineInstalled(pending) {
                config.engine = pending.rawValue
                persist()
                pendingEngineAfterDownload = nil
            }
        }
    }

    private var wineEnginePicker: some View {
        Picker("", selection: engineSelection) {
            Text(
                SettingInheritance.automaticLabel(
                    scope: "default",
                    effectiveDisplay: WineEngine.resolved(from: appState.configuration.defaultEngine).userFacingName
                )
            )
            .tag(SettingInheritance.automatic)

            ForEach(WineEngine.allCases) { engine in
                Text("\(engine.userFacingName) · \(WineEnginesViewModel.pickerStatusLabel(for: engine))")
                    .tag(engine.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 220, maxWidth: 320, minHeight: VermutHeight.field)
        .accessibilityLabel("Wine engine")
    }

    private var engineSelection: Binding<String> {
        Binding(
            get: {
                SettingInheritance.isAutomatic(config.engine)
                    ? SettingInheritance.automatic
                    : config.engine
            },
            set: { newValue in
                if newValue == SettingInheritance.automatic {
                    config.engine = SettingInheritance.automatic
                    persist()
                    return
                }
                guard let engine = WineEngine(rawValue: newValue) else { return }
                if EngineManager.shared.isEngineInstalled(engine) || engine == .grappleWine {
                    config.engine = engine.rawValue
                    persist()
                } else {
                    enginesModel.requestDownload(engine)
                }
            }
        )
    }

    private var effectiveEngineLine: String {
        let effective = StoreRecipe.effectiveEngine(config, global: appState.configuration)
        let inherited: String
        switch effective.source {
        case .global: inherited = "inherited from Settings"
        case .bottle: inherited = "set on this bottle"
        case .game: inherited = "set for this game"
        }
        return "\(effective.value.userFacingName) · \(inherited)"
    }

    private var selectedEngineRequiresGStreamer: Bool {
        StoreRecipe.effectiveEngine(config, global: appState.configuration).value.requiresGStreamer
    }

    private var gstreamerWarning: String? {
        let status = GStreamerProbe.probe()
        guard !status.isPresent else { return nil }
        return status.userFacingMessage
    }

    private func header(width: CGFloat) -> some View {
        Group {
            if width >= 900 {
                HStack(alignment: .center, spacing: VermutSpace.s4) {
                    identity
                    Spacer(minLength: VermutSpace.s3)
                    actions
                }
            } else {
                VStack(alignment: .leading, spacing: VermutSpace.s3) {
                    identity
                    actions
                }
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: VermutSpace.s4) {
            StoreLogoTile(store: store, size: 56)
            VStack(alignment: .leading, spacing: VermutSpace.s1) {
                HStack(spacing: VermutSpace.s2) {
                    Text(store.rawValue)
                        .font(VermutType.title)
                        .foregroundStyle(Color.Vermut.foreground)
                        .lineLimit(1)
                    VermutBadge(
                        kind: presentation.kind,
                        text: presentation.text,
                        systemImage: presentation.symbol,
                        showsDot: presentation.showsDot
                    )
                    .fixedSize()
                }
                Text(appState.bottlePathDisplay(for: store))
                    .font(VermutType.mono)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: VermutSpace.s2) {
            Button {
                appState.openCDrive(for: store)
            } label: {
                Label("Show C: drive", systemImage: "internaldrive")
            }
            .buttonStyle(VermutButtonStyle(kind: .outline))
            .help("Open this bottle’s C: drive in Finder")
            .fixedSize()

            if case .running = status {
                Button {
                    appState.stopStore(store)
                } label: {
                    Label("Quit", systemImage: "stop.circle")
                }
                .buttonStyle(VermutButtonStyle(kind: .outline))
                .fixedSize()
            }

            switch status {
            case .notInstalled, .error:
                Button(store == .epic ? "Sign in" : "Install") {
                    if store == .epic {
                        appState.signInEpic()
                    } else {
                        appState.installStore(store)
                    }
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .fixedSize()
            case .downloading, .installing:
                StoreInstallControls(store: store, status: status, fillWidth: false)
                    .frame(maxWidth: 280, alignment: .trailing)
            case .installed, .running:
                Button(store == .epic ? (appState.epicAccount == nil ? "Sign in" : "Open library") : store.openTitle) {
                    appState.launchStore(store)
                }
                .buttonStyle(VermutButtonStyle(kind: .primary))
                .fixedSize()
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VermutSpace.s6) {
                ForEach(BottleTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: VermutSpace.s2) {
                            Text(item.title)
                                .font(VermutType.bodyEmphasis)
                                .foregroundStyle(tab == item ? Color.Vermut.foreground : Color.Vermut.mutedForeground)
                                .lineLimit(1)
                            Rectangle()
                                .fill(tab == item ? Color.Vermut.foreground : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(VermutMotion.selection, value: tab)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.Vermut.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabBody(width: CGFloat) -> some View {
        switch tab {
        case .general:
            generalForm(width: width)
        case .graphics:
            graphicsForm(width: width)
        case .programs:
            programsPane
        case .logs:
            logsPane(width: width)
        }
    }

    private func generalForm(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Compatibility")
            formRow("Windows version", help: windowsHelp, width: width) {
                Picker("", selection: $config.windowsVersion) {
                    Text("Windows 10").tag("win10")
                    Text("Windows 8.1").tag("win81")
                    Text("Windows 7").tag("win7")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160, height: VermutHeight.field)
                .disabled(windowsLocked)
                .onChange(of: config.windowsVersion) { _, _ in persist() }
            }
            formRow("Retina mode", help: "Store windows render at standard resolution for stability.", width: width) {
                Toggle("", isOn: $config.enableHiDPI)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Color.Vermut.primary)
                    .disabled(true)
                    .onChange(of: config.enableHiDPI) { _, _ in persist() }
            }
            if store == .steam {
                formRow("Launch arguments", help: "Passed to steam.exe", width: width, stacked: true) {
                    Text("-no-cef-sandbox -cef-disable-gpu -noverifyfiles")
                        .font(VermutType.mono)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, VermutSpace.s2)
                        .padding(.vertical, VermutSpace.s2)
                        .frame(maxWidth: .infinity, minHeight: VermutHeight.field, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: VermutRadius.sm, style: .continuous)
                                .strokeBorder(Color.Vermut.input, lineWidth: 1)
                        )
                }
            }

            sectionTitle("Wine")
                .padding(.top, VermutSpace.s6)
            Text("Applies to the whole \(store.shortName) bottle. Individual games can override it later.")
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .padding(.bottom, VermutSpace.s2)
            formRow("Wine engine", help: "Used the next time you open this store", width: width) {
                wineEnginePicker
            }
            formRow("Version in use", help: "", width: width) {
                Text(effectiveEngineLine)
                    .font(VermutType.mono)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: VermutSpace.s2) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.Vermut.info)
                Text("Changing the engine does not affect games or saves. If the store is open, the change applies on the next launch.")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.infoSubtleForeground)
                    .lineSpacing(2)
            }
            .padding(.vertical, VermutSpace.s2)
            if case .running = status {
                HStack(alignment: .top, spacing: VermutSpace.s2) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.Vermut.warning)
                    Text("\(store.rawValue) is running. The new engine will be used when you reopen \(store.shortName).")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.warningSubtleForeground)
                        .lineSpacing(2)
                }
                .padding(.vertical, VermutSpace.s2)
            }
            if let gstreamerWarning, selectedEngineRequiresGStreamer {
                HStack(alignment: .top, spacing: VermutSpace.s2) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.Vermut.warning)
                    Text(gstreamerWarning)
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.warningSubtleForeground)
                        .lineSpacing(2)
                }
                .padding(.vertical, VermutSpace.s2)
            }
            formRow("DLL overrides", help: "How this bottle loads Direct3D", width: width) {
                Text(dllSummary)
                    .font(VermutType.mono)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            formRow("Wine configuration", help: "Opens the standard winecfg window for this bottle", width: width) {
                Button("Open winecfg") { appState.openWinecfg(for: store) }
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                    .disabled(!WineManager.shared.isStoreInstalled(store))
                    .fixedSize()
            }
        }
    }

    private func graphicsForm(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Graphics")
            formRow("Backend", help: graphicsHelp, width: width) {
                backendControl(width: width)
            }
            formRow(
                "D3DMetal",
                help: appState.hasD3DMetal
                    ? "Detected on this Mac"
                    : "Install Apple’s Game Porting Toolkit, then point Vermut to redist/lib in Settings › Components",
                width: width
            ) {
                HStack(spacing: VermutSpace.s2) {
                    VermutBadge(
                        kind: appState.hasD3DMetal ? .success : .neutral,
                        text: appState.hasD3DMetal ? "Found" : "Not found",
                        showsDot: appState.hasD3DMetal
                    )
                    if !appState.hasD3DMetal {
                        Button("Open guide") {
                            appState.settingsTab = .components
                            appState.section = .settings
                        }
                        .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
                    }
                }
            }
        }
    }

    private var windowsLocked: Bool { store == .epic || store == .gog }

    private var windowsHelp: String {
        windowsLocked
            ? "Locked for \(store.shortName): needs Windows 10"
            : "Reported to games and launchers"
    }

    private var graphicsHelp: String {
        switch store {
        case .steam:
            return "Stored on this bottle and used the next time you open the store"
        case .epic:
            return EpicStoreCopy.graphicsHelp
        case .gog:
            return "Locked for \(store.shortName): needs WineD3D"
        }
    }

    private var dllSummary: String {
        let global = appState.configuration
        let engine = StoreRecipe.effectiveEngine(config, global: global).value
        let backend = GraphicsBackend(rawValue: config.graphicsBackend) ?? .wined3d
        return DllOverridePolicy.userFacingSummary(engine: engine, backend: backend, store: store)
    }

    private var programsPane: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            sectionTitle("Programs")
            if WineManager.shared.isStoreInstalled(store) {
                HStack(spacing: VermutSpace.s3) {
                    StoreLogoTile(store: store, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.rawValue)
                            .font(VermutType.bodyEmphasis)
                        Text(resolvedStoreExecutable)
                            .font(VermutType.mono)
                            .foregroundStyle(Color.Vermut.mutedForeground)
                    }
                    Spacer()
                    Button(store.openTitle) { appState.launchStore(store) }
                        .buttonStyle(VermutButtonStyle(kind: .primary))
                        .fixedSize()
                }
                .padding(.vertical, VermutSpace.s3)
            } else {
                VermutEmptyState(
                    systemImage: "square.stack",
                    title: "No programs in this bottle",
                    message: store == .epic
                        ? "Sign in with Legendary to set up this bottle and list your Epic games."
                        : "Install the store to place its launcher in this prefix.",
                    actionTitle: store == .epic ? "Sign in" : "Install",
                    action: {
                        if store == .epic {
                            appState.signInEpic()
                        } else {
                            appState.installStore(store)
                        }
                    }
                )
            }
        }
    }

    private func logsPane(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: VermutSpace.s3) {
            if width >= 900 {
                HStack(spacing: VermutSpace.s3) {
                    sectionTitle("Logs")
                    Spacer(minLength: VermutSpace.s2)
                    logActions
                }
            } else {
                VStack(alignment: .leading, spacing: VermutSpace.s2) {
                    sectionTitle("Logs")
                    logActions
                }
            }
            LogTailPane(url: PathManager.shared.logURL(for: store))
        }
    }

    private var logActions: some View {
        HStack(spacing: VermutSpace.s2) {
            Button("Open in Finder") { appState.openLogs(for: store) }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
            Button("Copy diagnostics") { appState.copyDiagnosticReport() }
                .buttonStyle(VermutButtonStyle(kind: .outline, height: VermutHeight.buttonSmall, radius: VermutRadius.xsPlus, font: VermutType.callout, horizontalPadding: VermutSpace.s2))
        }
    }

    private func backendControl(width: CGFloat) -> some View {
        Group {
            if width < 900 {
                Picker("", selection: $config.graphicsBackend) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        Text(backend.shortLabel).tag(backend.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 140, minHeight: VermutHeight.field)
                .disabled(!StoreRecipe.allowsNativeGraphics(store))
                .onChange(of: config.graphicsBackend) { _, newValue in
                    let backend = GraphicsBackend(rawValue: newValue) ?? .wined3d
                    if !backendEnabled(backend) {
                        config.graphicsBackend = StoreRecipe.allowsNativeGraphics(store)
                            ? GraphicsBackend.dxmt.rawValue
                            : GraphicsBackend.wined3d.rawValue
                    }
                    persist()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            let selected = config.graphicsBackend == backend.rawValue
                            let enabled = backendEnabled(backend)
                            Button(backend.shortLabel) {
                                guard enabled else { return }
                                config.graphicsBackend = backend.rawValue
                                persist()
                            }
                            .font(VermutType.callout)
                            .foregroundStyle(selected ? Color.Vermut.primaryForeground : Color.Vermut.foreground)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(selected ? Color.Vermut.primary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.xsPlus, style: .continuous))
                            .buttonStyle(.plain)
                            .fixedSize()
                            .opacity(enabled ? 1 : 0.4)
                            .disabled(!enabled)
                            .help(backendHelp(backend))
                        }
                    }
                    .padding(2)
                }
                .frame(height: VermutHeight.field)
                .background(Color.Vermut.secondary)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
            }
        }
        .help(graphicsHelp)
    }

    private func backendEnabled(_ backend: GraphicsBackend) -> Bool {
        if backend == .d3dmetal && !appState.hasD3DMetal {
            return false
        }
        switch store {
        case .steam:
            return true
        case .epic:
            return true
        case .gog:
            return backend == .wined3d
        }
    }

    private func backendHelp(_ backend: GraphicsBackend) -> String {
        if backend == .d3dmetal && !appState.hasD3DMetal {
            return "Install the Game Porting Toolkit to use it. Open the guide in Settings › Components."
        }
        if !backendEnabled(backend) {
            return graphicsHelp
        }
        return backend.shortLabel
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                Text("Bottle")
                    .font(VermutType.headline)
                metaRow("Size", ByteFormat.string(appState.bottleSizes[store] ?? 0))
                metaRow("Engine", BottleLabels.engineName(config))
                metaRow("Graphics", BottleLabels.graphicsName(config, store: store))
                metaRow("Created", createdDate)
                metaRow("Last run", lastRun)
            }
            .vermutCard()

            HStack(alignment: .top, spacing: VermutSpace.s2) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.Vermut.info)
                VStack(alignment: .leading, spacing: VermutSpace.s1) {
                    Text("Tip")
                        .font(VermutType.bodyEmphasis)
                        .foregroundStyle(Color.Vermut.infoSubtleForeground)
                    Text("Games run better from the internal SSD. External drives work, but expect longer loads.")
                        .font(VermutType.body)
                        .foregroundStyle(Color.Vermut.infoSubtleForeground)
                        .lineSpacing(2)
                }
            }
            .padding(VermutSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Vermut.infoSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous)
                    .strokeBorder(Color.Vermut.infoBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: VermutSpace.s3) {
                Text("Danger zone")
                    .font(VermutType.headline)
                Text("Resetting removes this bottle and games installed in it. Store accounts and cloud saves are not stored here.")
                    .font(VermutType.body)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .lineSpacing(2)
                Button {
                    confirmDelete = true
                } label: {
                    Label("Reset bottle", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(VermutButtonStyle(kind: .destructiveOutline, fillWidth: true))
            }
            .vermutCard()
        }
        .frame(minWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(VermutType.headline)
            .foregroundStyle(Color.Vermut.foreground)
            .padding(.bottom, VermutSpace.s3)
    }

    private func formRow<Content: View>(
        _ title: String,
        help: String,
        width: CGFloat,
        stacked: Bool = false,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.Vermut.border).frame(height: 1)
            Group {
                if stacked || width < 900 {
                    VStack(alignment: .leading, spacing: VermutSpace.s2) {
                        formLabels(title, help)
                        control()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: VermutSpace.s6) {
                        formLabels(title, help)
                        Spacer(minLength: VermutSpace.s3)
                        control()
                    }
                }
            }
            .padding(.vertical, VermutSpace.s3)
            .frame(maxWidth: .infinity, minHeight: VermutHeight.formRow, alignment: .leading)
        }
    }

    private func formLabels(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(VermutType.bodyEmphasis)
                .foregroundStyle(Color.Vermut.foreground)
            Text(help)
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VermutSpace.s2) {
            Text(label)
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
            Spacer(minLength: VermutSpace.s2)
            Text(value)
                .font(VermutType.mono)
                .foregroundStyle(Color.Vermut.foreground)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: VermutHeight.sidebarRow)
    }

    private func persist() {
        let next = StoreRecipe.normalized(config, for: store)
        config = next
        appState.saveBottle(next, for: store)
    }

    private var resolvedStoreExecutable: String {
        if store == .epic {
            return LegendaryManager.shared.isBinaryInstalled()
                ? "engines/legendary/legendary"
                : "Legendary (not downloaded yet)"
        }
        if let url = WineManager.shared.resolvedExecutable(for: store) {
            let prefix = PathManager.shared.prefixURL(for: store).path
            if url.path.hasPrefix(prefix) {
                return String(url.path.dropFirst(prefix.count).drop(while: { $0 == "/" }))
            }
            return url.path
        }
        return store.executablePath
    }

    private var createdDate: String {
        let url = PathManager.shared.bottleURL(for: store)
        guard let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var lastRun: String {
        let url = PathManager.shared.logURL(for: store)
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return "—"
        }
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum BottleTab: String, CaseIterable, Identifiable {
    case general, graphics, programs, logs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .graphics: return "Graphics"
        case .programs: return "Programs"
        case .logs: return "Logs"
        }
    }
}

struct DeleteBottleSheet: View {
    let store: GameStore
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s4) {
            Text("Reset bottle")
                .font(VermutType.title)
            Text("Resetting deletes the \(store.rawValue) bottle (its Wine prefix) and any games installed in it. Your store account and cloud saves are not stored here and are not deleted.")
                .font(VermutType.body)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .lineSpacing(2)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(VermutButtonStyle(kind: .outline))
                Button("Reset bottle", action: onDelete)
                    .buttonStyle(VermutButtonStyle(kind: .destructiveSolid))
            }
        }
        .padding(VermutSpace.s6)
        .frame(width: 440)
        .background(Color.Vermut.popover)
    }
}
