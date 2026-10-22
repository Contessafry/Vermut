import Foundation
import Combine
import SwiftUI
import AppKit
import CaskLauncherCore

enum AppSection: Hashable {
    case stores
    case library
    case downloads
    case bottle(GameStore)
    case customBottle(UUID)
    case settings
}

enum SetupPhase: Equatable {
    case checking
    case permissions
    case rosetta
    case engine
    case stores
    case failed
}

@MainActor
final class AppState: ObservableObject {
    @Published var storeStatuses: [GameStore: StoreStatus] = [:]
    @Published var isSetupComplete = false
    @Published var setupProgress = 0.0
    @Published var setupMessage = ""
    @Published var configuration: AppConfiguration
    @Published var errorMessage: String?
    /// Neutral one-shot notice (e.g. "You're up to date"). Never shared with `errorMessage`.
    @Published var infoAlertMessage: String?
    @Published var infoAlertTitle: String = "You're up to date"
    @Published var setupFailed = false
    @Published var setupPhase: SetupPhase = .checking
    @Published var showOnboarding = true
    @Published var isCheckingSetup = true
    @Published var onboardingStoreSelection: Set<GameStore> = [.steam]
    @Published var section: AppSection = .stores
    /// Preferred Settings tab when opening Settings (e.g. Components for D3DMetal guide).
    @Published var settingsTab: SettingsTab = .general
    @Published var searchQuery = ""
    @Published var showingFilePicker = false
    @Published var installedGames: [InstalledGame] = []
    @Published var bottleSizes: [GameStore: Int64] = [:]
    @Published var hasRosetta = false
    /// True when Rosetta was already present so onboarding never showed the Rosetta step.
    @Published var rosettaSetupSkipped = false
    @Published var hasD3DMetal = false
    @Published var bottleToDelete: GameStore?
    @Published var epicAccount: LegendaryAccount?
    @Published var showingEpicAuth = false
    @Published var gameDownloads: [String: GameDownload] = [:]
    @Published var libraryFilterStore: GameStore?
    /// Library selection for the Game Settings inspector (⌥⌘I).
    @Published var selectedLibraryGameId: String?
    @Published var showingGameSettingsInspector = false
    /// Last engine/graphics applied to the Steam bottle session (for restart decisions).
    @Published var steamRuntimeProfile: BottleRuntimeProfile?
    /// Runtime profiles for store bottles (engine-change banner while running).
    @Published var storeRuntimeProfiles: [GameStore: BottleRuntimeProfile] = [:]
    /// Custom bottles from `custom-bottles.json`.
    @Published var customBottles: [CustomBottle] = []
    @Published var customBottleRunning: Set<UUID> = []
    @Published var showingNewBottleSheet = false
    /// One-shot Steam launch hang recovery (main/login window timeout).
    var steamLaunchWindowRecoveryUsed = false
    var steamWindowWatchTask: Task<Void, Never>?
    @Published var compatFeedbackSession: GameSession?
    @Published var compatFeedbackAutoDetectedCrash = false
    @Published var availableUpdate: (version: String, url: String, releaseNotes: String?, isPrerelease: Bool)?
    @Published var isCheckingForUpdate = false
    /// Fine-grained Steam first-run stage shown while status is .installing(.updatingClient).
    @Published var steamStage: SteamSetupStage?
    /// No visible Steam progress for a while: neutral "Still working…" + Retry.
    @Published var steamStalled = false
    /// Neutral, transient hint shown when a Steam/Wine window was brought to front.
    @Published var steamWindowHint: String?
    var steamRetryRequested = false
    let localNetwork = LocalNetworkPermission()
    private var permissionsContinuation: CheckedContinuation<Void, Never>?
    static let permissionsReviewedKey = "permissionsReviewed"
    var permissionsReviewed: Bool {
        UserDefaults.standard.bool(forKey: Self.permissionsReviewedKey)
    }

    /// Continue (or Skip) on the permissions step: resume first setup.
    func confirmPermissions() {
        localNetwork.skip()
        UserDefaults.standard.set(true, forKey: Self.permissionsReviewedKey)
        permissionsContinuation?.resume()
        permissionsContinuation = nil
    }
    @Published var compatibilityData: [String: GameCompatibility] = [:]

    private var statusTask: Task<Void, Never>?
    private var installTasks: [GameStore: Task<Void, Never>] = [:]
    private var sessionCheckTask: Task<Void, Never>?
    private static let setupCompleteDefaultsKey = "vermut.setupComplete"

    init() {
        configuration = (try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()

        for store in GameStore.allCases {
            storeStatuses[store] = .notInstalled
        }

        let engineReady = SystemSetup.shared.checkWineInstalled()
        let lastKnown = UserDefaults.standard.bool(forKey: Self.setupCompleteDefaultsKey)
        isSetupComplete = engineReady
        showOnboarding = !engineReady && !lastKnown
        isCheckingSetup = true

        Task {
            await checkSetup()
            await checkForUpdateOnLaunch()
        }
        
        startSessionMonitoring()
        fetchCompatibilityData()
        reloadCustomBottles()

        // Debug feedback trigger (works in release builds via env var)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VermutDebugTriggerCompatFeedback"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let session = notification.userInfo?["session"] as? GameSession,
                  let crash = notification.userInfo?["crash"] as? Bool else { return }
            self?.compatFeedbackSession = session
            self?.compatFeedbackAutoDetectedCrash = crash
        }
        
        // Check for debug env var to trigger test feedback
        if ProcessInfo.processInfo.environment["VERMUT_DEBUG_FEEDBACK"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let testSession = GameSession(
                    store: .steam,
                    gameId: "620",
                    gameName: "Portal 2",
                    engine: "vermut-wine",
                    graphics: "dxmt",
                    startTime: Date().addingTimeInterval(-600)
                )
                CompatibilityService.shared.triggerDebugFeedback(
                    session: testSession,
                    autoDetectedCrash: false
                )
            }
        }
    }

    var appVersion: String { VermutProject.version }

    var defaultEngine: WineEngine {
        WineEngine.resolved(from: configuration.defaultEngine)
    }

    var engineStatusLine: String {
        defaultEngine.userFacingName
    }

    var libraryCount: Int { installedGames.count }

    var activeDownloadCount: Int {
        storeStatuses.values.filter(\.isInstallInProgress).count
            + gameDownloads.values.filter { $0.error == nil }.count
    }

    var hasAnyInstalledStore: Bool {
        GameStore.allCases.contains { store in
            switch status(for: store) {
            case .installed, .running: return true
            default: return false
            }
        }
    }

    var allStoresInstalled: Bool {
        GameStore.allCases.allSatisfy { store in
            switch status(for: store) {
            case .installed, .running: return true
            default: return false
            }
        }
    }

    var runningStores: [GameStore] {
        GameStore.allCases.filter { storeStatuses[$0].map(isRunning) ?? false }
    }

    func status(for store: GameStore) -> StoreStatus {
        storeStatuses[store] ?? .notInstalled
    }

    func checkSetup() async {
        setupFailed = false
        errorMessage = nil
        // Keep the last known ready state so Onboarding does not flash while we check.
        setupProgress = 0
        setupPhase = .checking
        isCheckingSetup = true
        do {
            try PathManager.shared.ensureDirectoriesExist()

            if !permissionsReviewed {
                hasRosetta = (try? await SystemSetup.shared.checkRosetta()) ?? false
                setupPhase = .permissions
                setupMessage = "Permissions"
                isCheckingSetup = false
                await withCheckedContinuation { permissionsContinuation = $0 }
                isCheckingSetup = true
            }

            let rosetta = try await SystemSetup.shared.checkRosetta()
            hasRosetta = rosetta
            if !rosetta {
                rosettaSetupSkipped = false
                setupPhase = .rosetta
                setupMessage = "Installing Rosetta 2…"
                try await SystemSetup.shared.installRosetta()
                hasRosetta = true
            } else {
                rosettaSetupSkipped = true
            }

            if !SystemSetup.shared.checkWineInstalled() {
                setupPhase = .engine
                setupMessage = "Downloading Wine 11 with DXMT…"
                try await SystemSetup.shared.downloadDefaultEngine { [weak self] progress in
                    Task { @MainActor in
                        self?.setupProgress = progress * 0.7
                    }
                }
            }

            if !SystemSetup.shared.checkDXMTInstalled() {
                setupPhase = .engine
                setupMessage = "Downloading DXMT…"
                try await SystemSetup.shared.downloadDXMT { [weak self] progress in
                    Task { @MainActor in
                        self?.setupProgress = 0.7 + (progress * 0.3)
                    }
                }
            }

            hasD3DMetal = SystemSetup.shared.checkD3DMetalInstalled()
            setupProgress = 1
            setupPhase = .stores
            isSetupComplete = true
            isCheckingSetup = false
            UserDefaults.standard.set(true, forKey: Self.setupCompleteDefaultsKey)
            setupMessage = "Engine ready"

            for store in GameStore.allCases {
                updateStoreStatus(store)
            }
            refreshEpicAccount()
            refreshLibrary()
            refreshBottleMetrics()
            startStatusTimer()
        } catch {
            setupFailed = true
            setupPhase = .failed
            setupMessage = "Setup failed"
            errorMessage = error.localizedDescription
            isCheckingSetup = false
            if !isSetupComplete {
                showOnboarding = true
            }
        }
    }

    func finishOnboarding() {
        showOnboarding = false
        section = .stores
        let selected = StoreRecipe.selectableStores(onboardingStoreSelection)
        for store in GameStore.allCases where selected.contains(store) {
            if case .notInstalled = status(for: store) {
                installStore(store)
            }
        }
    }

    func skipOnboarding() {
        showOnboarding = false
        section = .stores
    }

    func updateStoreStatus(_ store: GameStore) {
        let running = WineManager.shared.isStoreRunning(store)
        storeStatuses[store] = StoreStatus.refreshed(
            current: storeStatuses[store],
            isRunning: running,
            isInstalled: WineManager.shared.isStoreInstalled(store)
        )
        if store == .steam, !running {
            steamRuntimeProfile = nil
        }
    }

    func retryStore(_ store: GameStore) {
        if store == .epic {
            signInEpic()
        } else if WineManager.shared.isStoreInstalled(store) {
            launchStore(store)
        } else {
            installStore(store)
        }
    }

    func installStore(_ store: GameStore) {
        guard !StoreRecipe.isComingSoon(store) else { return }
        installTasks[store]?.cancel()
        installTasks[store] = Task {
            do {
                storeStatuses[store] = .downloading(progress: 0)

                let bottleConfig = StoreRecipe.bottleConfiguration(
                    from: configuration,
                    for: store
                )

                try await WineManager.shared.installStore(
                    store,
                    config: bottleConfig,
                    progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self else { return }
                            if progress >= 0.999 {
                                self.storeStatuses[store] = .installing(.settingUp)
                            } else {
                                self.storeStatuses[store] = .downloading(progress: progress)
                            }
                        }
                    },
                    onSettingUp: { [weak self] in
                        Task { @MainActor in
                            self?.storeStatuses[store] = .installing(.settingUp)
                        }
                    },
                    onAwaitingWindow: { [weak self] in
                        Task { @MainActor in
                            self?.storeStatuses[store] = .installing(.awaitingWindow)
                        }
                    }
                )

                if store == .steam {
                    try await runSteamFirstUpdate(config: bottleConfig)
                    // Never show Installed for bootstrapper-only (steam.exe without SteamUI/CEF).
                    guard WineManager.shared.isStoreInstalled(.steam) else {
                        throw WineError.installerTimedOut(.steam)
                    }
                }
                storeStatuses[store] = .installed
                refreshLibrary()
                refreshBottleMetrics()
            } catch is CancellationError {
                updateStoreStatus(store)
            } catch let error as WineError where error.isCancelled {
                updateStoreStatus(store)
            } catch {
                storeStatuses[store] = .error(error.localizedDescription)
            }
        }
    }

    func cancelInstall(_ store: GameStore) {
        installTasks[store]?.cancel()
        installTasks[store] = nil
        WineManager.shared.cancelInstall(for: store)
        if WineManager.shared.isStoreInstalled(store) {
            storeStatuses[store] = .installed
        } else {
            storeStatuses[store] = .notInstalled
        }
    }

    func bringInstallerToFront(_ store: GameStore) {
        let needles = ["wine", "wine64", store.shortName.lowercased(), store.rawValue.lowercased()]
        for app in NSWorkspace.shared.runningApplications {
            let name = ((app.localizedName ?? "") + " " + (app.bundleIdentifier ?? "")).lowercased()
            if needles.contains(where: { name.contains($0) }) {
                app.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openWinecfg(for store: GameStore) {
        do {
            try WineManager.shared.openWinecfg(for: store)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Steam's bootstrapper downloads the real client on first launch and shows
    /// transient errors meanwhile. Start it ourselves, keep the card in a neutral
    /// "Updating" state, and only report failure if it never becomes ready.
    private func runSteamFirstUpdate(config: BottleConfiguration) async throws {
        let prefix = PathManager.shared.prefixURL(for: .steam)
        steamStage = .firstStart
        steamStalled = false
        storeStatuses[.steam] = .installing(.updatingClient)
        defer { steamStage = nil; steamStalled = false }
        var launchError = await startSteamFirstRun(config: config)
        // Onboarding / first-update path: watch continuously so the login window
        // is activated when it appears (not only at spawn time).
        watchSteamWindowsWhileRunning()
        var lastProgressChange = Date()
        var lastSignature = ""
        var lastLogSize = -1
        var lastLogGrowth = Date()
        var readySince: Date?
        var seenWindowPIDs = Set<pid_t>()
        var bootstrapRelaunches = 0
        let trace = CappedLogWriter.shared(for: PathManager.shared.logURL(for: .steam))
        let deadline = Date().addingTimeInterval(45 * 60)
        while Date() < deadline {
            try Task.checkCancellation()
            var snapshot = await Task.detached { SteamWindowWatcher.snapshot(prefix: prefix) }.value
            // Quiet period measured by Vermut itself (file mtimes in the bottle are unreliable).
            if snapshot.logSize != lastLogSize { lastLogSize = snapshot.logSize; lastLogGrowth = Date() }
            snapshot.inputs.secondsSinceLogChange = Date().timeIntervalSince(lastLogGrowth)
            var stage = SteamSetupEvaluator.stage(snapshot.inputs)
            // Ready must hold for a full quiet period before we commit to it.
            if stage == .ready {
                readySince = readySince ?? Date()
                if Date().timeIntervalSince(readySince!) < SteamSetupEvaluator.quietSeconds { stage = .finishing }
            } else {
                readySince = nil
            }
            if stage != steamStage {
                let i = snapshot.inputs
                trace.append(line: "[vermut] steam setup: \(stage.label) (updateDone=\(i.bootstrap?.updateCompleted ?? false) inProgress=\(i.bootstrap?.updateInProgress ?? false) files=\(i.clientFilesReady) helper=\(i.webhelperRunning) window=\(i.windowVisible) quiet=\(Int(i.secondsSinceLogChange ?? -1))s)")
            }
            if stage != steamStage { steamStage = stage }
            if let pid = snapshot.windowPID, !seenWindowPIDs.contains(pid) {
                seenWindowPIDs.insert(pid)
                SteamWindowWatcher.bringToFront(pid: pid)
                showSteamWindowHint()
            }
            if stage == .ready { return }

            // Bootstrapper often exits within ~2 min before the client update lands.
            // Auto-relaunch (bounded) instead of sitting on Updating/Finishing forever.
            let running = await Task.detached { WineManager.shared.isStoreRunning(.steam) }.value
            let clientReady = snapshot.inputs.clientFilesReady
                || SteamReadiness.isClientReady(inPrefix: prefix)
            if SteamReadiness.shouldRelaunchBootstrap(
                isRunning: running,
                clientReady: clientReady,
                relaunchesSoFar: bootstrapRelaunches
            ) {
                bootstrapRelaunches += 1
                steamStalled = false
                lastProgressChange = Date()
                lastSignature = ""
                seenWindowPIDs.removeAll()
                trace.append(line: "[vermut] steam setup: bootstrap exited before client ready; relaunch \(bootstrapRelaunches)/\(SteamReadiness.bootstrapRelaunchAttempts)")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                launchError = await startSteamFirstRun(config: config)
                watchSteamWindowsWhileRunning()
                continue
            }
            if !running, !clientReady, bootstrapRelaunches >= SteamReadiness.bootstrapRelaunchAttempts {
                throw launchError ?? WineError.installerTimedOut(.steam)
            }

            let signature = "\(stage)|\(snapshot.logSize)"
            if signature != lastSignature {
                lastSignature = signature
                lastProgressChange = Date()
                if steamStalled { steamStalled = false }
            } else if SteamSetupEvaluator.isStalled(secondsSinceProgress: Date().timeIntervalSince(lastProgressChange)) {
                if !steamStalled { steamStalled = true }
            }
            if steamRetryRequested {
                steamRetryRequested = false
                steamStalled = false
                lastProgressChange = Date()
                seenWindowPIDs.removeAll()
                try? WineManager.shared.stopStore(.steam)
                try await Task.sleep(nanoseconds: 3_000_000_000)
                launchError = await startSteamFirstRun(config: config)
                watchSteamWindowsWhileRunning()
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        // Only a real final failure: nothing usable after the full window.
        if SteamReadiness.isClientReady(inPrefix: prefix) { return }
        throw launchError ?? WineError.installerTimedOut(.steam)
    }

    /// Plain steam.exe start; wine can bounce the first launch right after
    /// SteamSetup exits, so retry a few times.
    private func startSteamFirstRun(config: BottleConfiguration) async -> Error? {
        var launchError: Error?
        for attempt in 0..<SteamReadiness.firstLaunchAttempts {
            do {
                try await WineManager.shared.launchStore(.steam, config: config, firstRunUpdate: true)
                recordSteamRuntimeProfile(for: config)
                return nil
            } catch {
                launchError = error
                if attempt + 1 < SteamReadiness.firstLaunchAttempts {
                    try? await Task.sleep(nanoseconds: SteamReadiness.firstLaunchRetryDelayNanos)
                }
            }
        }
        return launchError
    }

    func retrySteamSetup() { steamRetryRequested = true }

    func showSteamWindowHint() {
        steamWindowHint = "Steam window opened"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            steamWindowHint = nil
        }
    }

    /// Records the engine/graphics profile for the Steam session (every launch path).
    func recordSteamRuntimeProfile(for config: BottleConfiguration) {
        let backend = GraphicsBackend(rawValue: config.graphicsBackend) ?? .dxmt
        let inherited = StoreRecipe.effectiveEngine(config, global: configuration).value
        let profile = BottleRuntimeProfile(
            engine: EngineGraphicsPolicy.launchEngine(inherited, backend: backend),
            graphics: backend
        )
        steamRuntimeProfile = profile
        storeRuntimeProfiles[.steam] = profile
    }

    /// After a normal Steam launch, bring its first window to the front.
    func bringSteamWindowForward() {
        let prefix = PathManager.shared.prefixURL(for: .steam)
        Task { @MainActor in
            for _ in 0..<60 {
                let pid = await Task.detached { SteamWindowWatcher.snapshot(prefix: prefix).windowPID }.value
                if let pid {
                    SteamWindowWatcher.bringToFront(pid: pid)
                    showSteamWindowHint()
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Keep bringing new Steam login/alert windows forward while the bottle is running.
    func watchSteamWindowsWhileRunning() {
        steamWindowWatchTask?.cancel()
        let prefix = PathManager.shared.prefixURL(for: .steam)
        steamWindowWatchTask = Task { @MainActor in
            var seen = Set<pid_t>()
            while !Task.isCancelled {
                let running = await Task.detached { WineManager.shared.isStoreRunning(.steam) }.value
                guard running else { break }
                let snapshot = await Task.detached { SteamWindowWatcher.snapshot(prefix: prefix) }.value
                if let pid = snapshot.windowPID, !seen.contains(pid) {
                    seen.insert(pid)
                    SteamWindowWatcher.bringToFront(pid: pid)
                    showSteamWindowHint()
                }
                // Also catch smaller alert windows (min 200×150).
                let alertPID = await Task.detached {
                    SteamWindowWatcher.wineWindowPID(minWidth: 200, minHeight: 150)
                }.value
                if let alertPID, !seen.contains(alertPID) {
                    seen.insert(alertPID)
                    SteamWindowWatcher.bringToFront(pid: alertPID)
                    showSteamWindowHint()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// If Steam's main/login window never appears, restart Steam once (M-series hang).
    func scheduleSteamLaunchHangRecovery(config: BottleConfiguration) {
        Task { @MainActor in
            // Reasonable timeout for the first large window after launch.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            guard WineManager.shared.isStoreRunning(.steam) else { return }
            let hasBigWindow = await Task.detached {
                SteamWindowWatcher.wineWindowPID(minWidth: 600, minHeight: 400) != nil
            }.value
            guard !hasBigWindow else { return }
            guard !steamLaunchWindowRecoveryUsed else { return }
            steamLaunchWindowRecoveryUsed = true
            try? WineManager.shared.stopStore(.steam)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                try await WineManager.shared.launchStore(.steam, config: config)
                storeStatuses[.steam] = .running
                recordSteamRuntimeProfile(for: config)
                bringSteamWindowForward()
                watchSteamWindowsWhileRunning()
            } catch {
                storeStatuses[.steam] = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Custom bottles

    func reloadCustomBottles() {
        customBottles = (try? CustomBottleStore.shared.load()) ?? []
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func customBottle(id: UUID) -> CustomBottle? {
        customBottles.first { $0.id == id }
    }

    func registerCustomBottle(_ bottle: CustomBottle) throws {
        try CustomBottleStore.shared.upsert(bottle)
        reloadCustomBottles()
    }

    func updateCustomBottle(_ bottle: CustomBottle) {
        try? CustomBottleStore.shared.upsert(bottle)
        try? WineManager.shared.saveCustomBottleConfig(bottle.configuration, id: bottle.id)
        reloadCustomBottles()
    }

    func deleteCustomBottle(id: UUID) throws {
        try WineManager.shared.deleteCustomBottle(id: id)
        try CustomBottleStore.shared.remove(id: id)
        customBottleRunning.remove(id)
        reloadCustomBottles()
        if case .customBottle(let current) = section, current == id {
            section = .stores
        }
    }

    func setCustomBottleRunning(id: UUID, running: Bool) {
        var next = customBottleRunning
        if running {
            next.insert(id)
        } else {
            next.remove(id)
        }
        // Assign a new Set so @Published always notifies SwiftUI.
        customBottleRunning = next
    }

    /// Probe one bottle immediately (launch / page appear) without waiting for the timer.
    func refreshCustomBottleRunning(id: UUID) {
        let running = WineManager.shared.isCustomBottleRunning(id: id)
        setCustomBottleRunning(id: id, running: running)
    }

    func refreshAllCustomBottleRunning() {
        let ids = customBottles.map(\.id)
        let running = Set(ids.filter { WineManager.shared.isCustomBottleRunning(id: $0) })
        if customBottleRunning != running {
            customBottleRunning = running
        }
    }

    /// Stops all Vermut-owned Wine/Steam processes (app quit).
    func stopAllManagedWineProcesses() {
        steamWindowWatchTask?.cancel()
        WineManager.shared.stopAllVermutManagedProcesses()
        for store in GameStore.allCases {
            if case .running = storeStatuses[store] {
                storeStatuses[store] = .installed
            }
        }
        steamRuntimeProfile = nil
        storeRuntimeProfiles.removeAll()
        customBottleRunning.removeAll()
    }

    func launchStore(_ store: GameStore) {
        guard !StoreRecipe.isComingSoon(store) else { return }
        if store == .epic {
            openEpicLibraryOrSignIn()
            return
        }
        Task {
            do {
                var bottleConfig = try WineManager.shared.loadBottleConfig(for: store)
                let engine = StoreLaunchRecipe.engine(
                    for: store,
                    defaultEngine: configuration.defaultEngine,
                    bottleEngine: bottleConfig.engine
                )
                bottleConfig.engine = engine.rawValue
                bottleConfig = StoreRecipe.normalized(bottleConfig, for: store)
                try WineManager.shared.saveBottleConfig(bottleConfig, for: store)
                try await WineManager.shared.launchStore(store, config: bottleConfig)
                storeStatuses[store] = .running
                if store == .steam {
                    recordSteamRuntimeProfile(for: bottleConfig)
                    steamLaunchWindowRecoveryUsed = false
                    bringSteamWindowForward()
                    watchSteamWindowsWhileRunning()
                    scheduleSteamLaunchHangRecovery(config: bottleConfig)
                } else {
                    let backend = GraphicsBackend(rawValue: bottleConfig.graphicsBackend) ?? .dxmt
                    let inherited = WineEngine.resolved(from: bottleConfig.engine)
                    storeRuntimeProfiles[store] = BottleRuntimeProfile(
                        engine: EngineGraphicsPolicy.launchEngine(inherited, backend: backend),
                        graphics: backend
                    )
                }

                Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    updateStoreStatus(store)
                }
            } catch {
                storeStatuses[store] = .error(error.localizedDescription)
            }
        }
    }

    func openEpicLibraryOrSignIn() {
        if epicAccount != nil {
            libraryFilterStore = .epic
            section = .library
            refreshLibrary()
        } else {
            signInEpic()
        }
    }

    func signInEpic() {
        Task {
            do {
                let bottleConfig = StoreRecipe.bottleConfiguration(from: configuration, for: .epic)
                if !WineManager.shared.isStoreInstalled(.epic) {
                    storeStatuses[.epic] = .downloading(progress: 0)
                    try await WineManager.shared.installStore(
                        .epic,
                        config: bottleConfig,
                        progress: { [weak self] progress in
                            Task { @MainActor in
                                guard let self else { return }
                                if progress >= 0.999 {
                                    self.storeStatuses[.epic] = .installing(.settingUp)
                                } else {
                                    self.storeStatuses[.epic] = .downloading(progress: progress)
                                }
                            }
                        },
                        onSettingUp: { [weak self] in
                            Task { @MainActor in
                                self?.storeStatuses[.epic] = .installing(.settingUp)
                            }
                        }
                    )
                    storeStatuses[.epic] = .installed
                }
                refreshEpicAccount()
                if epicAccount == nil {
                    showingEpicAuth = true
                } else {
                    openEpicLibraryOrSignIn()
                }
            } catch {
                storeStatuses[.epic] = .error(error.localizedDescription)
            }
        }
    }

    func completeEpicLogin(code: String) async throws {
        _ = try LegendaryManager.shared.login(code: code)
        refreshEpicAccount()
        refreshLibrary()
        storeStatuses[.epic] = .installed
    }

    func logoutEpic() {
        try? LegendaryManager.shared.logout()
        epicAccount = nil
        refreshLibrary()
    }

    func refreshEpicAccount() {
        epicAccount = LegendaryManager.shared.account()
    }

    func launchGame(_ game: InstalledGame) {
        let resolved = resolveLaunchSettings(for: game)
        let launchConfig = resolved.launchConfiguration
        let wineDebug = WineLogLevel.effectiveWineDebug(level: resolved.logLevel.value)

        if resolved.requiresStagingInstall,
           !EngineManager.shared.isEngineInstalled(.staging) {
            infoAlertTitle = String(localized: "Wine Staging required", comment: "DXVK needs Staging")
            infoAlertMessage = String(
                localized: "DXVK needs Wine Staging (Vermut Wine has no Vulkan loader). Download it from Settings › Wine Engines, then play again.",
                comment: "Offer Staging download before DXVK launch"
            )
            settingsTab = .wineEngines
            return
        }

        if game.store == .epic {
            Task {
                do {
                    startGameSession(
                        store: game.store,
                        gameId: game.appId,
                        gameName: game.name,
                        resolved: resolved
                    )
                    try await WineManager.shared.launchEpicGame(
                        appName: game.appId,
                        config: launchConfig,
                        wineDebug: wineDebug
                    )
                    storeStatuses[.epic] = .running
                    Task {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        updateStoreStatus(.epic)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return
        }

        if game.store == .steam {
            launchSteamGame(game, resolved: resolved, launchConfig: launchConfig)
            return
        }

        startGameSession(
            store: game.store,
            gameId: game.appId,
            gameName: game.name,
            resolved: resolved
        )
        Task {
            do {
                try await WineManager.shared.launchStore(
                    game.store,
                    config: launchConfig,
                    wineDebug: wineDebug
                )
                storeStatuses[game.store] = .running
                Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    updateStoreStatus(game.store)
                }
            } catch {
                storeStatuses[game.store] = .error(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Play a Steam title with `-applaunch`. Client WINEDEBUG stays `-all` (Verbose does not flood Steam).
    private func launchSteamGame(
        _ game: InstalledGame,
        resolved: ResolvedLaunchSettings,
        launchConfig: BottleConfiguration
    ) {
        let needed = BottleRuntimeProfile(resolved: resolved)
        let running = WineManager.shared.isStoreRunning(.steam)
        let processEngine = running ? WineManager.shared.runningSteamEngine() : nil
        let restart = SteamGameLaunch.needsClientRestart(
            isRunning: running,
            runningProfile: steamRuntimeProfile,
            runningEngineFromProcess: processEngine,
            needed: needed
        )

        if restart {
            infoAlertTitle = String(localized: "Steam will restart", comment: "Engine mismatch title")
            infoAlertMessage = SteamGameLaunch.restartInfoMessage(neededEngine: needed.engine)
        }

        startGameSession(
            store: game.store,
            gameId: game.appId,
            gameName: game.name,
            resolved: resolved
        )

        Task {
            do {
                if restart {
                    try? WineManager.shared.stopStore(.steam)
                    steamRuntimeProfile = nil
                    // Let wineserver exit before starting with the game engine.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                try await WineManager.shared.launchSteamGame(
                    appId: game.appId,
                    config: launchConfig
                )
                steamRuntimeProfile = needed
                storeRuntimeProfiles[.steam] = needed
                storeStatuses[.steam] = .running
                bringSteamWindowForward()
                watchSteamWindowsWhileRunning()
                Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    updateStoreStatus(.steam)
                }
            } catch {
                storeStatuses[.steam] = .error(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Settings → bottle → game resolution for one library title.
    func resolveLaunchSettings(for game: InstalledGame) -> ResolvedLaunchSettings {
        let bottle = StoreRecipe.normalized(loadBottle(game.store), for: game.store, global: configuration)
        let gameConfig = loadGameSettings(for: game)
        return StoreRecipe.resolveLaunchSettings(
            game: gameConfig,
            bottle: bottle,
            global: configuration,
            store: game.store
        )
    }

    func loadGameSettings(for game: InstalledGame) -> GameConfiguration {
        GameSettingsStore.load(store: game.store, appId: game.appId)
    }

    func saveGameSettings(_ config: GameConfiguration, for game: InstalledGame) {
        do {
            try GameSettingsStore.save(config, store: game.store, appId: game.appId)
        } catch {
            errorMessage = "Failed to save game settings: \(error.localizedDescription)"
        }
    }

    func resetGameSettings(for game: InstalledGame) {
        do {
            try GameSettingsStore.reset(store: game.store, appId: game.appId)
        } catch {
            errorMessage = "Failed to reset game settings: \(error.localizedDescription)"
        }
    }

    func openGameSettings(for game: InstalledGame) {
        selectedLibraryGameId = game.id
        section = .library
        showingGameSettingsInspector = true
    }

    func toggleGameSettingsInspector() {
        if section != .library {
            section = .library
        }
        if selectedLibraryGameId == nil {
            selectedLibraryGameId = installedGames.first?.id
        }
        showingGameSettingsInspector.toggle()
    }

    var selectedLibraryGame: InstalledGame? {
        guard let id = selectedLibraryGameId else { return nil }
        return installedGames.first { $0.id == id }
    }

    func installEpicGame(_ game: InstalledGame) {
        let id = game.id
        gameDownloads[id] = GameDownload(store: .epic, appId: game.appId, name: game.name, progress: 0)
        section = .downloads
        Task.detached { [weak self] in
            do {
                try LegendaryManager.shared.install(appName: game.appId) { fraction, line in
                    Task { @MainActor in
                        guard let self else { return }
                        self.gameDownloads[id] = GameDownload(
                            store: .epic,
                            appId: game.appId,
                            name: game.name,
                            progress: fraction,
                            detail: line
                        )
                    }
                }
                await MainActor.run {
                    self?.gameDownloads.removeValue(forKey: id)
                    self?.refreshLibrary()
                    self?.refreshBottleMetrics()
                }
            } catch is CancellationError {
                await MainActor.run { self?.gameDownloads.removeValue(forKey: id) }
            } catch let error as LegendaryError where error == .cancelled {
                await MainActor.run { self?.gameDownloads.removeValue(forKey: id) }
            } catch {
                await MainActor.run {
                    self?.gameDownloads[id] = GameDownload(
                        store: .epic,
                        appId: game.appId,
                        name: game.name,
                        progress: 0,
                        error: error.localizedDescription
                    )
                }
            }
        }
    }

    func cancelEpicGameDownload(_ download: GameDownload) {
        LegendaryManager.shared.cancelInstall()
        gameDownloads.removeValue(forKey: download.id)
    }

    func stopStore(_ store: GameStore) {
        Task {
            do {
                try WineManager.shared.stopStore(store)
                storeStatuses[store] = .installed
            } catch {
                errorMessage = "Failed to stop \(store.rawValue): \(error.localizedDescription)"
            }
        }
    }

    func resetStore(_ store: GameStore) {
        Task {
            do {
                try WineManager.shared.deletePrefix(for: store)
                storeStatuses[store] = .notInstalled
                if store == .epic {
                    epicAccount = nil
                }
                if case .bottle(let current) = section, current == store {
                    section = .stores
                }
                refreshLibrary()
                refreshBottleMetrics()
            } catch {
                errorMessage = "Failed to reset \(store.rawValue): \(error.localizedDescription)"
            }
        }
    }

    func openBottlesFolder() {
        NSWorkspace.shared.open(PathManager.shared.bottlesURL)
    }

    func openCDrive(for store: GameStore) {
        let driveC = PathManager.shared.prefixURL(for: store).appendingPathComponent("drive_c")
        if FileManager.default.fileExists(atPath: driveC.path) {
            NSWorkspace.shared.open(driveC)
        } else {
            NSWorkspace.shared.open(PathManager.shared.bottleURL(for: store))
        }
    }

    func openLogs(for store: GameStore) {
        let url = PathManager.shared.bottleLogsURL(for: store)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(PathManager.shared.bottlesURL)
        }
    }

    func generateDiagnosticReport() async -> String {
        (try? await Diagnostics.shared.generateReport()) ?? "Failed to generate report"
    }

    func copyDiagnosticReport() {
        Task {
            let report = await generateDiagnosticReport()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report, forType: .string)
        }
    }

    func saveConfiguration() {
        do {
            configuration.defaultDXMTVersion = ComponentVersion.canonicalTag(configuration.defaultDXMTVersion)
            try ConfigurationManager.shared.saveConfiguration(configuration)
            if DXMTVersionManager.shared.isInstalled(configuration.defaultDXMTVersion) {
                try? DXMTVersionManager.shared.setActiveVersion(configuration.defaultDXMTVersion)
            }
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    func saveBottle(_ config: BottleConfiguration, for store: GameStore) {
        do {
            try WineManager.shared.saveBottleConfig(config, for: store)
        } catch {
            errorMessage = "Failed to save bottle: \(error.localizedDescription)"
        }
    }

    func loadBottle(_ store: GameStore) -> BottleConfiguration {
        (try? WineManager.shared.loadBottleConfig(for: store)) ?? BottleConfiguration()
    }

    func refreshLibrary() {
        let epic = (try? LegendaryManager.shared.libraryGames()) ?? []
        installedGames = StoreLibrary.shared.listAll(epicOverlay: epic.isEmpty ? nil : epic)
    }

    func refreshBottleMetrics() {
        for store in GameStore.allCases {
            let url = PathManager.shared.bottleURL(for: store)
            bottleSizes[store] = ByteFormat.directorySize(at: url)
        }
        hasD3DMetal = SystemSetup.shared.checkD3DMetalInstalled()
    }

    func launchExecutable(at url: URL) {
        Task {
            do {
                let bottleConfig = BottleConfiguration(
                    engine: configuration.defaultEngine,
                    graphicsBackend: configuration.defaultGraphicsBackend,
                    enableHiDPI: configuration.enableHiDPI,
                    windowsVersion: configuration.windowsVersion
                )
                try WineManager.shared.launchExecutable(at: url.path, config: bottleConfig)
            } catch {
                errorMessage = "Failed to launch executable: \(error.localizedDescription)"
            }
        }
    }

    func bottlePathDisplay(for store: GameStore) -> String {
        DataDirectoryMigration.displayPath(
            of: PathManager.shared.bottleURL(for: store),
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            deferred: PathManager.shared.migrationDeferred
        )
    }

    private func isRunning(_ status: StoreStatus) -> Bool {
        if case .running = status { return true }
        return false
    }

    private func startStatusTimer() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                // `ps` + filesystem probes run off the main thread (they caused UI jank).
                let probes = await Task.detached { () -> [(GameStore, Bool, Bool)] in
                    GameStore.allCases.map {
                        ($0, WineManager.shared.isStoreRunning($0), WineManager.shared.isStoreInstalled($0))
                    }
                }.value
                for (store, running, installed) in probes {
                    self.storeStatuses[store] = StoreStatus.refreshed(
                        current: self.storeStatuses[store], isRunning: running, isInstalled: installed)
                    if store == .steam, !running {
                        self.steamRuntimeProfile = nil
                        self.storeRuntimeProfiles[.steam] = nil
                    } else if !running {
                        self.storeRuntimeProfiles[store] = nil
                    }
                }
                // Custom bottle Running dots — probe every tick so sidebar updates live.
                let customIDs = self.customBottles.map(\.id)
                let runningCustom = await Task.detached {
                    Set(customIDs.filter { WineManager.shared.isCustomBottleRunning(id: $0) })
                }.value
                if self.customBottleRunning != runningCustom {
                    self.customBottleRunning = runningCustom
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    
    private func startGameSession(
        store: GameStore,
        gameId: String,
        gameName: String?,
        resolved: ResolvedLaunchSettings
    ) {
        guard CompatibilityService.shared.isPromptEnabled else { return }

        GameSessionTracker.shared.startSession(
            store: store,
            gameId: gameId,
            gameName: gameName,
            engine: resolved.engine.value.rawValue,
            graphics: graphicsIdentifier(resolved.graphics.value)
        )
    }

    private func startGameSession(store: GameStore, gameId: String, gameName: String?, config: BottleConfiguration) {
        let resolved = ResolvedLaunchSettings(
            engine: EffectiveSetting(value: WineEngine.resolved(from: config.engine), source: .bottle),
            graphics: EffectiveSetting(
                value: GraphicsBackend(rawValue: config.graphicsBackend) ?? .wined3d,
                source: .bottle
            ),
            dxmtVersion: EffectiveSetting(
                value: ComponentVersion.canonicalTag(
                    SettingInheritance.isAutomatic(config.dxmtVersion)
                        ? configuration.defaultDXMTVersion
                        : config.dxmtVersion
                ),
                // Keep `.global` when Automatic so launchConfiguration does not pin DXMT.
                source: SettingInheritance.isAutomatic(config.dxmtVersion) ? .global : .bottle
            ),
            logLevel: EffectiveSetting(
                value: WineLogLevel.resolved(
                    from: SettingInheritance.isAutomatic(config.logLevel)
                        ? configuration.defaultLogLevel
                        : config.logLevel
                ),
                source: SettingInheritance.isAutomatic(config.logLevel) ? .global : .bottle
            ),
            bottleBase: config
        )
        startGameSession(store: store, gameId: gameId, gameName: gameName, resolved: resolved)
    }
    
    private func graphicsIdentifier(_ backend: GraphicsBackend) -> String {
        switch backend {
        case .dxmt: return "dxmt"
        case .dxvk: return "dxvk"
        case .d3dmetal: return "d3dmetal"
        case .wined3d: return "wined3d"
        }
    }
    
    private func startSessionMonitoring() {
        sessionCheckTask?.cancel()
        sessionCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.checkForEndedSessions()
            }
        }
    }
    
    private func checkForEndedSessions() async {
        guard CompatibilityService.shared.isPromptEnabled else { return }
        
        for store in GameStore.allCases {
            let wasRunning = storeStatuses[store].map { self.isRunning($0) } ?? false
            updateStoreStatus(store)
            let nowRunning = storeStatuses[store].map { self.isRunning($0) } ?? false
            
            if wasRunning && !nowRunning {
                checkAllSessionsForStore(store)
            }
        }
    }
    
    private func checkAllSessionsForStore(_ store: GameStore) {
        let allSessions = GameSessionTracker.shared.getAllSessions(for: store)
        for session in allSessions {
            _ = GameSessionTracker.shared.endSession(store: store, gameId: session.gameId)
            handleSessionEnd(session)
        }
    }
    
    private func checkSessionEnd(store: GameStore) {
        guard CompatibilityService.shared.isPromptEnabled else { return }
        
        let wasRunning = runningStores.contains(store)
        updateStoreStatus(store)
        let isRunning = runningStores.contains(store)
        
        if wasRunning && !isRunning {
            checkAllSessionsForStore(store)
        }
    }
    
    private func handleSessionEnd(_ session: GameSession) {
        guard let gameName = session.gameName, !gameName.isEmpty,
              session.gameId != "launcher" else {
            return
        }
        
        // Note: Currently tracks store process, not individual game process.
        // This means the banner appears when the *store* closes, which may be
        // after playing multiple games in one session. We detect crashes based
        // on very short sessions (<1 min), but a user closing the game normally
        // after 5+ minutes will not be marked as a crash.
        let playMinutes = session.playMinutes
        let autoDetectedCrash = playMinutes < 1
        
        guard playMinutes >= 5 || autoDetectedCrash else { return }
        
        Task { @MainActor in
            compatFeedbackSession = session
            compatFeedbackAutoDetectedCrash = autoDetectedCrash
        }
    }
    
    func dismissCompatFeedback() {
        compatFeedbackSession = nil
        compatFeedbackAutoDetectedCrash = false
    }
    
    func fetchCompatibilityData() {
        Task {
            do {
                let data = try await CompatibilityService.shared.fetchCompatibilityData()
                
                await MainActor.run {
                    var map: [String: GameCompatibility] = [:]
                    for game in data.games {
                        let key = "\(game.store):\(game.gameId)"
                        map[key] = game
                    }
                    compatibilityData = map
                }
            } catch {
                print("Failed to fetch compatibility data: \(error)")
            }
        }
    }
    
    func getCompatibility(for game: InstalledGame) -> GameCompatibility? {
        let key = "\(game.store.identifier):\(game.appId)"
        return compatibilityData[key]
    }
    
    func checkForUpdateOnLaunch() async {
        let channel = configuration.resolvedUpdateChannel
        let result = await UpdateChecker.shared.checkForUpdate(
            currentVersion: VermutProject.version,
            channel: channel
        )
        await MainActor.run {
            if case .updateAvailable(let version, let url, let notes, let isPre) = result {
                availableUpdate = (version, url, notes, isPre)
            }
        }
    }
    
    func checkForUpdateManually() async {
        await MainActor.run {
            isCheckingForUpdate = true
            infoAlertMessage = nil
        }
        let channel = configuration.resolvedUpdateChannel
        let result = await UpdateChecker.shared.checkForUpdate(
            currentVersion: VermutProject.version,
            channel: channel,
            force: true
        )
        await MainActor.run {
            isCheckingForUpdate = false
            if case .updateAvailable(let version, let url, let notes, let isPre) = result {
                availableUpdate = (version, url, notes, isPre)
                infoAlertMessage = nil
            } else if case .upToDate = result {
                availableUpdate = nil
                errorMessage = nil
                // Neutral info alert — never reuse errorMessage (that alert title is "Something went wrong").
                infoAlertTitle = "You're up to date"
                infoAlertMessage = "Vermut \(VermutProject.version) is the latest on the \(channel.userFacingName) channel."
            } else {
                availableUpdate = nil
                infoAlertMessage = nil
                errorMessage = "Could not check for updates. Check your network connection."
            }
        }
    }

    func dismissInfoAlert() {
        infoAlertMessage = nil
    }
    
    func dismissUpdate() {
        guard let update = availableUpdate else { return }
        UpdateChecker.shared.dismissUpdate(version: update.version)
        availableUpdate = nil
    }
    
    func performUpdate() {
        Task {
            await updateApp()
        }
    }
    
    private func updateApp() async {
        let runningStoresList = runningStores
        if !runningStoresList.isEmpty {
            await MainActor.run {
                let storeNames = runningStoresList.map { $0.rawValue }.joined(separator: ", ")
                errorMessage = "Quit \(storeNames) before updating."
            }
            return
        }
        
        await MainActor.run {
            infoAlertTitle = "Updating"
            infoAlertMessage = "Downloading and installing the update…"
        }
        
        let script = "curl -fsSL https://raw.githubusercontent.com/Contessafry/Vermut/main/install.sh | bash"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                relaunchApp()
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    infoAlertMessage = nil
                    errorMessage = "Update failed: \(output)"
                }
            }
        } catch {
            await MainActor.run {
                infoAlertMessage = nil
                errorMessage = "Update failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [bundlePath]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
