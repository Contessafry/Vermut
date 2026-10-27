import SwiftUI
import AppKit
import CaskLauncherCore

/// Library inspector: Settings → bottle → game overrides for one title.
struct GameSettingsInspector: View {
    let game: InstalledGame
    @EnvironmentObject var appState: AppState
    @State private var config = GameConfiguration.automatic
    @State private var confirmResetAll = false
    @State private var pendingEngineAfterDownload: WineEngine?
    @State private var showingFindConfiguration = false
    @StateObject private var enginesModel = WineEnginesViewModel()
    @StateObject private var d3dMetalModel = D3DMetalViewModel()
    @StateObject private var findConfiguration = FindConfigurationController()

    private var bottle: BottleConfiguration {
        StoreRecipe.normalized(
            appState.loadBottle(game.store),
            for: game.store,
            global: appState.configuration
        )
    }

    private var global: AppConfiguration { appState.configuration }

    private var effectiveGraphics: GraphicsBackend {
        let resolved = SettingInheritance.resolveGraphics(
            game: config.graphicsBackend,
            bottle: bottle.graphicsBackend,
            global: global.defaultGraphicsBackend
        ).value
        return game.store == .gog ? .wined3d : resolved
    }

    private var resolvedPreview: ResolvedLaunchSettings {
        GameSettingsResolver.resolve(
            game: config,
            bottle: bottle,
            global: global,
            store: game.store
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VermutSpace.s4) {
                header
                antiCheatSection
                compatSection
                engineSection
                graphicsSection
                dxmtSection
                d3dMetalBlock
                if game.store == .steam {
                    overlaySection
                }
                logLevelSection
                launchOptionsSection
                findConfigurationSection
                actionButtons
                nextLaunchNote
            }
            .padding(VermutSpace.s4)
        }
        .frame(minWidth: 320)
        .background(Color.Vermut.background)
        .onAppear(perform: reload)
        .onChange(of: game.id) { _, _ in reload() }
        .onChange(of: enginesModel.busyEngine) { _, busy in
            guard busy == nil, let pending = pendingEngineAfterDownload else { return }
            if EngineManager.shared.isEngineInstalled(pending) {
                config.engine = pending.rawValue
                persist()
                pendingEngineAfterDownload = nil
            }
        }
        .sheet(isPresented: $showingFindConfiguration) {
            FindConfigurationSheet(game: game, controller: findConfiguration)
                .environmentObject(appState)
        }
        .confirmationDialog(
            String(localized: "Reset settings for \(game.name)?", comment: "Confirm reset all game settings"),
            isPresented: $confirmResetAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset all", comment: "Confirm reset game settings"), role: .destructive) {
                config.resetAll()
                persist()
            }
            Button(String(localized: "Cancel", comment: "Cancel reset"), role: .cancel) {}
        } message: {
            Text(String(localized: "Every value will return to Automatic.", comment: "Reset all explanation"))
        }
        .confirmationDialog(
            enginesModel.pendingDownload.map { enginesModel.confirmSheetTitle(for: $0) }
                ?? String(localized: "Download engine?", comment: "Engine download title"),
            isPresented: Binding(
                get: { enginesModel.pendingDownload != nil },
                set: { if !$0 { enginesModel.cancelPendingDownload() } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Download", comment: "Confirm engine download")) {
                if let engine = enginesModel.pendingDownload {
                    pendingEngineAfterDownload = engine
                }
                enginesModel.confirmPendingDownload()
            }
            Button(String(localized: "Cancel", comment: "Cancel engine download"), role: .cancel) {
                enginesModel.cancelPendingDownload()
            }
        } message: {
            if let engine = enginesModel.pendingDownload {
                Text(enginesModel.confirmSheetMessage(for: engine))
            }
        }
    }

    private func reload() {
        config = appState.loadGameSettings(for: game)
        enginesModel.refresh()
        d3dMetalModel.rescan()
        appState.hasD3DMetal = d3dMetalModel.isUsable
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text(String(localized: "Game Settings", comment: "Inspector title"))
                .font(VermutType.headline)
                .foregroundStyle(Color.Vermut.foreground)
            Text(
                String(
                    localized: "\(game.name) · \(game.store.shortNameForInheritance). “Automatic” values follow the \(game.store.shortNameForInheritance) bottle, which in turn follows Settings.",
                    comment: "Game settings inheritance intro"
                )
            )
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var engineSection: some View {
        let help: String? = resolvedPreview.engineForcedForDXVK
            ? String(
                localized: "Wine Staging is required for DXVK (Vermut Wine has no Vulkan loader).",
                comment: "DXVK forces Staging help"
            )
            : nil
        return settingRow(
            title: String(localized: "Wine engine", comment: "Game settings field"),
            field: \.engine,
            helpWhenAutomatic: help,
            accessibilityLabel: engineAccessibilityLabel
        ) {
            Picker("", selection: engineSelection) {
                Text(
                    GameSettingsResolver.automaticEngineLabel(
                        bottle: bottle,
                        global: global,
                        store: game.store,
                        effectiveGraphics: effectiveGraphics
                    )
                )
                .tag(SettingInheritance.automatic)
                ForEach(WineEngine.allCases) { engine in
                    Text(
                        EngineGraphicsPolicy.enginePickerLabel(
                            for: engine,
                            effectiveBackend: effectiveGraphics,
                            statusSuffix: WineEnginesViewModel.pickerStatusLabel(for: engine)
                        )
                    )
                    .tag(engine.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var graphicsSection: some View {
        settingRow(
            title: String(localized: "Graphics backend", comment: "Game settings field"),
            field: \.graphicsBackend,
            helpWhenAutomatic: nil,
            accessibilityLabel: graphicsAccessibilityLabel
        ) {
            Picker("", selection: graphicsSelection) {
                Text(
                    GameSettingsResolver.automaticGraphicsLabel(
                        bottle: bottle,
                        global: global,
                        store: game.store
                    )
                )
                .tag(SettingInheritance.automatic)
                ForEach(GraphicsBackend.allCases) { backend in
                    Text(EngineGraphicsPolicy.graphicsPickerLabel(for: backend))
                        .tag(backend.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var dxmtSection: some View {
        let dxmtActive = effectiveGraphics == .dxmt
        return settingRow(
            title: String(localized: "DXMT version", comment: "Game settings field"),
            field: \.dxmtVersion,
            helpWhenAutomatic: String(
                localized: "Only applies with DXMT backend.",
                comment: "DXMT version help"
            ),
            accessibilityLabel: dxmtAccessibilityLabel
        ) {
            Picker("", selection: dxmtSelection) {
                Text(
                    GameSettingsResolver.automaticDXMTLabel(
                        bottle: bottle,
                        global: global,
                        store: game.store
                    )
                )
                .tag(SettingInheritance.automatic)
                ForEach(DXMTVersionManager.shared.installedVersions(), id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!dxmtActive)
            .opacity(dxmtActive ? 1 : 0.5)
        }
    }

    private var d3dMetalBlock: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack {
                Text(String(localized: "D3DMetal", comment: "Game settings D3DMetal block"))
                    .font(VermutType.bodyEmphasis)
                Spacer(minLength: VermutSpace.s2)
                VermutBadge(
                    kind: d3dMetalModel.isUsable ? .success : .neutral,
                    text: d3dMetalModel.isUsable
                        ? String(localized: "Found", comment: "D3DMetal found badge")
                        : String(localized: "Not installed", comment: "D3DMetal missing badge"),
                    showsDot: d3dMetalModel.isUsable
                )
            }
            if !d3dMetalModel.isUsable {
                Text(
                    String(
                        localized: "Install the Game Porting Toolkit to use it.",
                        comment: "D3DMetal missing help"
                    )
                )
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
                Button(String(localized: "Open the guide", comment: "Open D3DMetal install guide")) {
                    appState.settingsTab = .components
                    appState.section = .settings
                    appState.showingGameSettingsInspector = false
                }
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
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Vermut.secondary)
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            d3dMetalModel.isUsable
                ? String(localized: "D3DMetal, found", comment: "a11y")
                : String(localized: "D3DMetal, not installed", comment: "a11y")
        )
    }

    private var antiCheatSection: some View {
        Group {
            if let entry = AntiCheatCatalog.lookup(
                store: game.store,
                appId: game.appId,
                name: game.name
            ) {
                HStack(alignment: .top, spacing: VermutSpace.s2) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(Color.Vermut.warning)
                    VStack(alignment: .leading, spacing: VermutSpace.s1) {
                        Text(entry.libraryWarning)
                            .font(VermutType.bodyEmphasis)
                            .foregroundStyle(Color.Vermut.warningSubtleForeground)
                        Text(
                            String(
                                localized: "Kernel anti-cheat data comes from Are We Anti-Cheat Yet? (areweanticheatyet.com). Linux/Proton “Supported” does not mean it will run in Wine on macOS.",
                                comment: "Anti-cheat source note"
                            )
                        )
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(VermutSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Vermut.warningSubtle)
                .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var compatSection: some View {
        if let compat = appState.getCompatibility(for: game) {
            VStack(alignment: .leading, spacing: VermutSpace.s2) {
                Text(String(localized: "Community compatibility", comment: "Game settings compat"))
                    .font(VermutType.bodyEmphasis)
                CompatibilityBadge(compat: compat)
                if let recommended = compat.effectiveRecommended {
                    Text("Recommended backend: \(KnownNotWorkingCombo.graphicsName(recommended))")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                } else if !compat.effectiveKnownNotWorking.isEmpty {
                    Text(
                        "No working reports yet. Known not working: "
                            + compat.effectiveKnownNotWorking.map(\.displayLabel).joined(separator: ", ")
                    )
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(VermutSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Vermut.secondary)
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Toggle(isOn: overlayBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Steam overlay", comment: "Game settings overlay"))
                        .font(VermutType.bodyEmphasis)
                    Text(
                        String(
                            localized: "Off by default. The overlay can hang games on DXMT.",
                            comment: "Steam overlay help"
                        )
                    )
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Color.Vermut.primary)
            if config.steamOverlayEnabled {
                Text(String(localized: "Modified for this game", comment: "Override indicator"))
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            config.steamOverlayEnabled
                ? String(localized: "Steam overlay, on", comment: "a11y")
                : String(localized: "Steam overlay, off", comment: "a11y")
        )
    }

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { config.steamOverlayEnabled },
            set: { newValue in
                config.steamOverlayEnabled = newValue
                persist()
            }
        )
    }

    private var launchOptionsSection: some View {
        let isOverridden = !config.launchOptions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(spacing: VermutSpace.s2) {
                if isOverridden {
                    Circle()
                        .fill(Color.Vermut.info)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(String(localized: "Launch options", comment: "Game settings field"))
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
            }
            Picker("", selection: launchOptionsSelection) {
                Text(String(localized: "None", comment: "No launch options")).tag("")
                ForEach(FindLaunchOption.searchSet.filter { !$0.arguments.isEmpty }) { option in
                    Text(option.displayName).tag(option.argumentString)
                }
                if isOverridden,
                   FindLaunchOption.searchSet.allSatisfy({ $0.argumentString != config.launchOptions }) {
                    Text(config.launchOptions).tag(config.launchOptions)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if isOverridden {
                HStack(spacing: VermutSpace.s1) {
                    Text(String(localized: "Modified for this game", comment: "Override indicator"))
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Text("·")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Button(String(localized: "Reset", comment: "Reset one game setting")) {
                        config.launchOptions = ""
                        persist()
                    }
                    .buttonStyle(.plain)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.info)
                }
            } else {
                Text(
                    String(
                        localized: "Passed after Steam -applaunch. Leave empty unless a game needs Unity flags such as -force-glcore.",
                        comment: "Launch options help"
                    )
                )
                .font(VermutType.captionRegular)
                .foregroundStyle(Color.Vermut.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(launchOptionsAccessibilityLabel)
    }

    private var findConfigurationSection: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            Text(String(localized: "Find configuration", comment: "Find configuration section"))
                .font(VermutType.bodyEmphasis)
            Text(
                String(
                    localized: "If this game will not start, try engines, graphics, overlay, and a few launch options automatically.",
                    comment: "Find configuration help"
                )
            )
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Find configuration", comment: "Find configuration button")) {
                findConfiguration.prepare(
                    game: game,
                    appState: appState,
                    d3dMetalInstalled: appState.hasD3DMetal || d3dMetalModel.isUsable
                )
                showingFindConfiguration = true
            }
            .buttonStyle(VermutButtonStyle(kind: .outline))
            .disabled(!game.isInstalled)
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Vermut.secondary)
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
    }

    private var logLevelSection: some View {
        let steamNote = game.store == .steam
            ? String(
                localized: "“Verbose” slows the game down — use it only when reporting a problem. On Steam, Verbose does not apply to the Steam client (client logs stay quiet).",
                comment: "Log level help Steam"
            )
            : String(
                localized: "“Verbose” slows the game down — use it only when reporting a problem.",
                comment: "Log level help"
            )
        return settingRow(
            title: String(localized: "Log level", comment: "Game settings field"),
            field: \.logLevel,
            helpWhenAutomatic: steamNote,
            accessibilityLabel: logLevelAccessibilityLabel
        ) {
            Picker("", selection: logLevelSelection) {
                Text(
                    GameSettingsResolver.automaticLogLevelLabel(
                        bottle: bottle,
                        global: global,
                        store: game.store
                    )
                )
                .tag(SettingInheritance.automatic)
                ForEach(WineLogLevel.allCases) { level in
                    Text(level.displayName).tag(level.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: VermutSpace.s2) {
            Button(String(localized: "Open log folder", comment: "Game settings action")) {
                openLogFolder()
            }
            .buttonStyle(VermutButtonStyle(kind: .outline))

            Button(String(localized: "Reset all", comment: "Game settings action")) {
                confirmResetAll = true
            }
            .buttonStyle(VermutButtonStyle(kind: .outline))
            .disabled(!config.hasOverrides)
        }
    }

    private var nextLaunchNote: some View {
        HStack(alignment: .top, spacing: VermutSpace.s2) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.Vermut.info)
            Text(
                String(
                    localized: "Changes apply from the next game launch.",
                    comment: "Game settings footer"
                )
            )
            .font(VermutType.captionRegular)
            .foregroundStyle(Color.Vermut.infoSubtleForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VermutSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Vermut.infoSubtle)
        .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))
    }

    // MARK: - Row helper

    private func settingRow<Content: View>(
        title: String,
        field: WritableKeyPath<GameConfiguration, String>,
        helpWhenAutomatic: String?,
        accessibilityLabel: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        let isOverridden = !SettingInheritance.isAutomatic(config[keyPath: field])
        return VStack(alignment: .leading, spacing: VermutSpace.s2) {
            HStack(spacing: VermutSpace.s2) {
                if isOverridden {
                    Circle()
                        .fill(Color.Vermut.info)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
            }
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            if isOverridden {
                HStack(spacing: VermutSpace.s1) {
                    Text(String(localized: "Modified for this game", comment: "Override indicator"))
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Text("·")
                        .font(VermutType.captionRegular)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                    Button(String(localized: "Reset", comment: "Reset one game setting")) {
                        config[keyPath: field] = SettingInheritance.automatic
                        persist()
                    }
                    .buttonStyle(.plain)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.info)
                }
            } else if let helpWhenAutomatic {
                Text(helpWhenAutomatic)
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Bindings

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
                    pendingEngineAfterDownload = engine
                    enginesModel.requestDownload(engine)
                }
            }
        )
    }

    private var graphicsSelection: Binding<String> {
        Binding(
            get: {
                SettingInheritance.isAutomatic(config.graphicsBackend)
                    ? SettingInheritance.automatic
                    : config.graphicsBackend
            },
            set: { newValue in
                if newValue == SettingInheritance.automatic {
                    config.graphicsBackend = SettingInheritance.automatic
                    persist()
                    return
                }
                guard let backend = GraphicsBackend(rawValue: newValue), backendEnabled(backend) else {
                    return
                }
                config.graphicsBackend = backend.rawValue
                persist()
            }
        )
    }

    private var dxmtSelection: Binding<String> {
        Binding(
            get: {
                SettingInheritance.isAutomatic(config.dxmtVersion)
                    ? SettingInheritance.automatic
                    : config.dxmtVersion
            },
            set: { newValue in
                config.dxmtVersion = newValue
                persist()
            }
        )
    }

    private var launchOptionsSelection: Binding<String> {
        Binding(
            get: { config.launchOptions },
            set: { newValue in
                config.launchOptions = newValue
                persist()
            }
        )
    }

    private var logLevelSelection: Binding<String> {
        Binding(
            get: {
                SettingInheritance.isAutomatic(config.logLevel)
                    ? SettingInheritance.automatic
                    : config.logLevel
            },
            set: { newValue in
                config.logLevel = newValue
                persist()
            }
        )
    }

    // MARK: - Helpers

    private func backendEnabled(_ backend: GraphicsBackend) -> Bool {
        if backend == .d3dmetal && !appState.hasD3DMetal && !d3dMetalModel.isUsable {
            return false
        }
        if !StoreRecipe.allowsNativeGraphics(game.store) {
            return backend == .wined3d
        }
        return true
    }

    private func persist() {
        appState.saveGameSettings(config, for: game)
    }

    private func openLogFolder() {
        let url = PathManager.shared.bottleLogsURL(for: game.store)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            appState.errorMessage = String(
                localized: "No logs yet — launch the game at least once.",
                comment: "Missing log folder"
            )
        }
    }

    private var engineAccessibilityLabel: String {
        let value: String
        if SettingInheritance.isAutomatic(config.engine) {
            value = GameSettingsResolver.automaticEngineLabel(
                bottle: bottle,
                global: global,
                store: game.store,
                effectiveGraphics: effectiveGraphics
            )
        } else if resolvedPreview.engineForcedForDXVK {
            value = EngineGraphicsPolicy.stagingRequiredByDXVKLabel
        } else {
            value = WineEngine(rawValue: config.engine)?.userFacingName ?? config.engine
        }
        let suffix = SettingInheritance.isAutomatic(config.engine)
            ? ""
            : ", " + String(localized: "modified for this game", comment: "a11y override")
        return String(localized: "Wine engine, \(value)\(suffix)", comment: "a11y")
    }

    private var graphicsAccessibilityLabel: String {
        let value: String
        if SettingInheritance.isAutomatic(config.graphicsBackend) {
            value = GameSettingsResolver.automaticGraphicsLabel(
                bottle: bottle,
                global: global,
                store: game.store
            )
        } else {
            value = GraphicsBackend(rawValue: config.graphicsBackend)?.shortLabel ?? config.graphicsBackend
        }
        let suffix = SettingInheritance.isAutomatic(config.graphicsBackend)
            ? ""
            : ", " + String(localized: "modified for this game", comment: "a11y override")
        return String(localized: "Graphics backend, \(value)\(suffix)", comment: "a11y")
    }

    private var dxmtAccessibilityLabel: String {
        let value = SettingInheritance.isAutomatic(config.dxmtVersion)
            ? GameSettingsResolver.automaticDXMTLabel(
                bottle: bottle,
                global: global,
                store: game.store
            )
            : config.dxmtVersion
        return String(localized: "DXMT version, \(value)", comment: "a11y")
    }

    private var launchOptionsAccessibilityLabel: String {
        let value = config.launchOptions.isEmpty
            ? String(localized: "None", comment: "No launch options")
            : config.launchOptions
        return String(localized: "Launch options, \(value)", comment: "a11y")
    }

    private var logLevelAccessibilityLabel: String {
        let value = SettingInheritance.isAutomatic(config.logLevel)
            ? GameSettingsResolver.automaticLogLevelLabel(
                bottle: bottle,
                global: global,
                store: game.store
            )
            : WineLogLevel.resolved(from: config.logLevel).displayName
        return String(localized: "Log level, \(value)", comment: "a11y")
    }
}
