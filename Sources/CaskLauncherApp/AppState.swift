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
    case settings
}

enum SetupPhase: Equatable {
    case checking
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
    @Published var setupFailed = false
    @Published var setupPhase: SetupPhase = .checking
    @Published var showOnboarding = true
    @Published var isCheckingSetup = true
    @Published var onboardingStoreSelection: Set<GameStore> = [.steam]
    @Published var section: AppSection = .stores
    @Published var searchQuery = ""
    @Published var showingFilePicker = false
    @Published var installedGames: [InstalledGame] = []
    @Published var bottleSizes: [GameStore: Int64] = [:]
    @Published var hasRosetta = false
    @Published var hasD3DMetal = false
    @Published var bottleToDelete: GameStore?
    @Published var epicAccount: LegendaryAccount?
    @Published var showingEpicAuth = false
    @Published var gameDownloads: [String: GameDownload] = [:]
    @Published var libraryFilterStore: GameStore?
    @Published var compatFeedbackSession: GameSession?
    @Published var compatFeedbackAutoDetectedCrash = false
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
        }
        
        startSessionMonitoring()
        fetchCompatibilityData()
        
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

            let rosetta = try await SystemSetup.shared.checkRosetta()
            hasRosetta = rosetta
            if !rosetta {
                setupPhase = .rosetta
                setupMessage = "Installing Rosetta 2…"
                try await SystemSetup.shared.installRosetta()
                hasRosetta = true
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
        let selected = onboardingStoreSelection
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
        storeStatuses[store] = StoreStatus.refreshed(
            current: storeStatuses[store],
            isRunning: WineManager.shared.isStoreRunning(store),
            isInstalled: WineManager.shared.isStoreInstalled(store)
        )
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

    func launchStore(_ store: GameStore) {
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
        if game.store == .epic {
            Task {
                do {
                    let bottleConfig = StoreRecipe.normalized(loadBottle(.epic), for: .epic)
                    startGameSession(store: game.store, gameId: game.appId, gameName: game.name, config: bottleConfig)
                    try await WineManager.shared.launchEpicGame(appName: game.appId, config: bottleConfig)
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
        
        let bottleConfig = loadBottle(game.store)
        startGameSession(store: game.store, gameId: game.appId, gameName: game.name, config: bottleConfig)
        launchStore(game.store)
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
            try ConfigurationManager.shared.saveConfiguration(configuration)
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
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                for store in GameStore.allCases {
                    self.updateStoreStatus(store)
                }
            }
        }
    }
    
    private func startGameSession(store: GameStore, gameId: String, gameName: String?, config: BottleConfiguration) {
        guard CompatibilityService.shared.isPromptEnabled else { return }
        
        let engine = WineEngine.resolved(from: config.engine)
        let graphics = GraphicsBackend(rawValue: config.graphicsBackend) ?? .wined3d
        
        GameSessionTracker.shared.startSession(
            store: store,
            gameId: gameId,
            gameName: gameName,
            engine: engine.rawValue,
            graphics: graphicsIdentifier(graphics)
        )
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
}
