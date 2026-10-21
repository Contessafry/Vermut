import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class WineManager: @unchecked Sendable {
    public static let shared = WineManager()

    /// After the installer process has been running this long, the UI asks the
    /// user to finish the wizard window instead of sitting at 100%.
    public static let awaitingInstallerWindowDelay: TimeInterval = 8

    private let fileManager = FileManager.default
    private let installerLock = NSLock()
    private var installerProcesses: [String: Process] = [:]
    private var cancelledInstalls: Set<String> = []

    private init() {}

    private func appConfiguration() -> AppConfiguration {
        (try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration()
    }

    /// Resolves Automatic → Settings, then DXVK→staging when needed.
    private func resolvedEngine(for store: GameStore, config: BottleConfiguration) -> WineEngine {
        let global = appConfiguration()
        var engine = StoreRecipe.effectiveEngine(config, global: global).value
        let backend = graphicsBackend(config)
        if backend == .dxvk, engine == .grappleWine {
            engine = .staging
        }
        return engine
    }

    public func createPrefix(for store: GameStore, config: BottleConfiguration) async throws {
        let engine = resolvedEngine(for: store, config: config)
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }

        let bottleURL = PathManager.shared.bottleURL(for: store)
        let prefixURL = PathManager.shared.prefixURL(for: store)
        let logsURL = PathManager.shared.bottleLogsURL(for: store)

        if fileManager.fileExists(atPath: prefixURL.path) {
            return
        }

        try fileManager.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: prefixURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true)

        let bottleConfigURL = PathManager.shared.bottleConfigURL(for: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(config)
        try configData.write(to: bottleConfigURL)

        var environment = buildEnvironment(for: store, config: config)
        environment["WINEPREFIX"] = prefixURL.path

        let bootProcess = Process()
        bootProcess.executableURL = wineExecutable
        bootProcess.arguments = ["wineboot", "-i"]
        bootProcess.environment = environment

        let logURL = PathManager.shared.logURL(for: store)
        let logPipe = CappedLogWriter.shared(for: logURL).makeProcessPipe()
        bootProcess.standardOutput = logPipe
        bootProcess.standardError = logPipe

        try bootProcess.run()
        bootProcess.waitUntilExit()


        guard bootProcess.terminationStatus == 0 else {
            throw WineError.prefixCreationFailed
        }

        try await configurePrefix(for: store, config: config, engine: engine)
    }

    private func configurePrefix(for store: GameStore, config: BottleConfiguration, engine: WineEngine) async throws {
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }

        let prefixURL = PathManager.shared.prefixURL(for: store)
        var environment = buildEnvironment(for: store, config: config)
        environment["WINEPREFIX"] = prefixURL.path

        try ensureDXMTPlacement(engine: engine, config: config, prefixURL: prefixURL, store: store)

        let winecfg = Process()
        winecfg.executableURL = wineExecutable
        winecfg.arguments = ["winecfg", "-v", config.windowsVersion]
        winecfg.environment = environment
        try winecfg.run()
        winecfg.waitUntilExit()

        var ops = DllOverridePolicy.registryWrites(
            engine: engine,
            backend: graphicsBackend(config),
            store: store
        )

        if store != .steam, config.enableHiDPI {
            ops.append(
                .add(WineRegWrite(
                    key: "HKCU\\Software\\Wine\\Mac Driver",
                    value: "RetinaMode",
                    data: "y"
                ))
            )
        }

        try apply(ops, wineExecutable: wineExecutable, environment: environment)
    }

    public func installStore(
        _ store: GameStore,
        config: BottleConfiguration,
        progress: @escaping @Sendable (Double) -> Void,
        onSettingUp: (@Sendable () -> Void)? = nil,
        onAwaitingWindow: (@Sendable () -> Void)? = nil
    ) async throws {
        let config = StoreRecipe.normalized(config, for: store)
        if store == .epic {
            try await installEpicBottle(config: config, progress: progress, onSettingUp: onSettingUp)
            return
        }
        let resolved = await StoreInstaller.resolvedDownload(for: store)
        let installerURL = PathManager.shared.cacheURL.appendingPathComponent(resolved.filename)
        let key = store.identifier

        _ = mutateInstallerState { cancelledInstalls.remove(key) }

        if !fileManager.fileExists(atPath: installerURL.path) {
            do {
                try await DownloadClient.download(from: resolved.url, to: installerURL, progress: { value in
                    // Never report 1.0 as "still downloading" — the UI switches to Setting up.
                    if value < 0.999 {
                        progress(value)
                    }
                })
            } catch is DownloadError {
                throw WineError.downloadFailed
            }
        }
        try throwIfInstallCancelled(store)
        onSettingUp?()

        try await createPrefix(for: store, config: config)
        try throwIfInstallCancelled(store)

        let engine = resolvedEngine(for: store, config: config)
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }

        let prefixURL = PathManager.shared.prefixURL(for: store)
        var environment = buildEnvironment(for: store, config: config)
        environment["WINEPREFIX"] = prefixURL.path

        let installerProcess = Process()
        installerProcess.executableURL = wineExecutable
        installerProcess.arguments = StoreInstaller.wineArguments(
            installerHostPath: installerURL.path,
            store: store
        )
        installerProcess.environment = environment

        let logURL = PathManager.shared.logURL(for: store)
        let logPipe = CappedLogWriter.shared(for: logURL).makeProcessPipe()
        installerProcess.standardOutput = logPipe
        installerProcess.standardError = logPipe

        onSettingUp?()
        try installerProcess.run()
        mutateInstallerState { installerProcesses[key] = installerProcess }

        let awaitTask = Task { [weak self] in
            let ns = UInt64(Self.awaitingInstallerWindowDelay * 1_000_000_000)
            try await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            guard self?.isInstallerProcessRunning(key) == true else { return }
            onAwaitingWindow?()
        }

        // GOG's setup auto-starts `GalaxyClient.exe /firstRun` while it is still
        // registering services; that run fails ("Essential components … missing")
        // and blocks setup. Stop only that child; Vermut opens GOG afterwards.
        let firstRunGuard: Task<Void, Never>? = store == .gog ? Task.detached {
            while !Task.isCancelled {
                for pid in GOGFirstRun.pids(in: PrefixRuntime.processPIDLines(), prefixPath: prefixURL.path) {
                    kill(pid, SIGTERM)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } : nil

        let waitResult = ProcessWait.waitUntilExit(
            installerProcess,
            timeout: StoreInstaller.timeout(for: store)
        )
        awaitTask.cancel()
        firstRunGuard?.cancel()
        if store == .gog {
            waitForWineserver(prefix: prefixURL, engine: engine, timeout: 30)
        }
        let wasCancelled = mutateInstallerState { () -> Bool in
            installerProcesses.removeValue(forKey: key)
            let cancelled = cancelledInstalls.contains(key)
            cancelledInstalls.remove(key)
            return cancelled
        }

        if wasCancelled || Task.isCancelled {
            try? killPrefix(prefix: prefixURL, engine: engine)
            throw WineError.cancelled
        }

        if case .timedOut = waitResult {
            try? killPrefix(prefix: prefixURL, engine: engine)
            throw WineError.installerTimedOut(store)
        }

        if store == .steam {
            try? SteamHelper.shared.restoreOriginalSteamWebHelper(in: prefixURL)
            try await configurePrefix(for: store, config: config, engine: engine)
        }

        guard StoreExecutable.resolve(in: prefixURL, store: store) != nil else {
            if case .exited(let status) = waitResult, status != 0 {
                throw WineError.installerFailed(store, status)
            }
            throw WineError.executableNotFound
        }
    }

    private func installEpicBottle(
        config: BottleConfiguration,
        progress: @escaping @Sendable (Double) -> Void,
        onSettingUp: (@Sendable () -> Void)?
    ) async throws {
        _ = mutateInstallerState { cancelledInstalls.remove(GameStore.epic.identifier) }
        try await LegendaryManager.shared.ensureBinary { value in
            if value < 0.999 {
                progress(value)
            }
        }
        try throwIfInstallCancelled(.epic)
        onSettingUp?()
        var config = config
        if graphicsBackend(config) == .dxvk {
            try await ensureEngineInstalled(.staging)
            config.engine = WineEngine.staging.rawValue
        }
        try await createPrefix(for: .epic, config: config)
        try throwIfInstallCancelled(.epic)
        try fileManager.createDirectory(
            at: PathManager.shared.legendaryConfigURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: LegendaryManager.shared.gamesBasePath(),
            withIntermediateDirectories: true
        )
        try applyEpicGraphics(config: config)
    }

    public func cancelInstall(for store: GameStore) {
        let key = store.identifier
        let process = mutateInstallerState { () -> Process? in
            cancelledInstalls.insert(key)
            return installerProcesses.removeValue(forKey: key)
        }
        process?.terminate()
        if let config = try? loadBottleConfig(for: store) {
            let engine = resolvedEngine(for: store, config: config)
            try? killPrefix(prefix: PathManager.shared.prefixURL(for: store), engine: engine)
        }
    }

    public func openWinecfg(for store: GameStore) throws {
        let config = StoreRecipe.normalized(
            (try? loadBottleConfig(for: store)) ?? BottleConfiguration(),
            for: store
        )
        let engine = resolvedEngine(for: store, config: config)
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }
        let prefixURL = PathManager.shared.prefixURL(for: store)
        guard fileManager.fileExists(atPath: prefixURL.path) else {
            throw WineError.prefixCreationFailed
        }
        var environment = buildEnvironment(for: store, config: config)
        environment["WINEPREFIX"] = prefixURL.path
        try launchDetached(
            executable: wineExecutable,
            arguments: ["winecfg"],
            environment: environment,
            workingDirectory: nil,
            logURL: PathManager.shared.logURL(for: store)
        )
    }

    private func isInstallerProcessRunning(_ key: String) -> Bool {
        mutateInstallerState { installerProcesses[key]?.isRunning == true }
    }

    private func throwIfInstallCancelled(_ store: GameStore) throws {
        let cancelled = mutateInstallerState { cancelledInstalls.contains(store.identifier) }
        if cancelled || Task.isCancelled {
            throw WineError.cancelled
        }
    }

    private func mutateInstallerState<T>(_ body: () -> T) -> T {
        installerLock.lock()
        defer { installerLock.unlock() }
        return body()
    }

    public func launchStore(
        _ store: GameStore,
        config: BottleConfiguration,
        wineDebug: String? = nil,
        firstRunUpdate: Bool = false
    ) async throws {
        if store == .epic {
            return
        }
        var config = StoreRecipe.normalized(config, for: store)
        let engine = resolvedEngine(for: store, config: config)
        // Concrete engine id so buildEnvironment / logs match main (1.1.3) after Automatic resolve.
        config.engine = engine.rawValue
        guard let layout = PathManager.shared.engineLayout(for: engine) else {
            throw WineError.wineNotInstalled
        }

        let prefixURL = PathManager.shared.prefixURL(for: store)
        let candidates = StoreExecutable.launchCandidates(in: prefixURL, store: store)
        guard let executablePath = candidates.first else {
            throw WineError.executableNotFound
        }

        if store == .steam {
            try? SteamHelper.shared.restoreOriginalSteamWebHelper(in: prefixURL)
            try migrateSteamBottleIfNeeded(prefixURL: prefixURL, engine: engine, config: config)
            try ensureDXMTPlacement(engine: engine, config: config, prefixURL: prefixURL, store: store)
            // A wineserver left over from setup or `wine reg` may run without msync.
            if !isStoreRunning(store) {
                waitForWineserver(prefix: prefixURL, engine: engine)
            }
        } else {
            try configureLauncherBottle(for: store, config: config, engine: engine)
        }

        let wineBinary = layout.launcherBinary(forWindowsExecutable: executablePath)
        var environment = buildEnvironment(for: store, config: config, wineDebug: wineDebug)
        environment["WINEPREFIX"] = prefixURL.path
        environment["WINELOADER"] = wineBinary.path

        let recipe = StoreLaunchRecipe.build(
            store: store,
            executable: executablePath,
            wineLibDir: layout.wineLibDir,
            firstRunUpdate: firstRunUpdate
        )
        for (key, value) in recipe.environment {
            environment[key] = value
        }
        // Per-game / bottle log level, then VERMUT_WINEDEBUG (host override always wins).
        applyWineDebug(&environment, preferred: wineDebug)

        let logURL = PathManager.shared.logURL(for: store)
        appendLaunchLog(
            StoreLaunchRecipe.launchLogLine(
                store: store,
                engine: engine,
                wine: wineBinary,
                wineserver: layout.wineserverExecutable
            ) + " exe=\(executablePath.path) winedebug=\(environment["WINEDEBUG"] ?? "")",
            to: logURL
        )
        appendLaunchLog(
            StoreLaunchRecipe.launchEnvironmentSummary(
                engineRoot: PathManager.shared.engineURL(for: engine),
                wine: wineBinary,
                environment: environment
            ),
            to: logURL
        )

        try launchDetached(
            executable: wineBinary,
            arguments: recipe.arguments,
            environment: environment,
            workingDirectory: recipe.workingDirectory,
            logURL: logURL
        )
    }

    public func launchEpicGame(
        appName: String,
        config: BottleConfiguration,
        wineDebug: String? = nil
    ) async throws {
        var config = StoreRecipe.normalized(config, for: .epic)
        if graphicsBackend(config) == .dxvk {
            try await ensureEngineInstalled(.staging)
            config.engine = WineEngine.staging.rawValue
        }
        let engine = resolvedEngine(for: .epic, config: config)
        config.engine = engine.rawValue
        try await createPrefix(for: .epic, config: config)
        try applyEpicGraphics(config: config)
        guard let layout = PathManager.shared.engineLayout(for: engine) else {
            throw WineError.wineNotInstalled
        }
        let wine = layout.wine64Executable ?? layout.wineExecutable
        let prefixURL = PathManager.shared.prefixURL(for: .epic)
        var environment = buildEnvironment(for: .epic, config: config, wineDebug: wineDebug)
        environment["WINEPREFIX"] = prefixURL.path
        environment["WINELOADER"] = wine.path
        environment["WINEARCH"] = "win64"
        if graphicsBackend(config) == .dxvk {
            environment["WINEDLLOVERRIDES"] = EpicVulkanPolicy.dxvkOverrideString
        }
        applyWineDebug(&environment, preferred: wineDebug)
        let logURL = PathManager.shared.logURL(for: .epic)
        appendLaunchLog(
            "Vermut: launching epic game \(appName) engine=\(engine.rawValue) wine=\(wine.path) prefix=\(prefixURL.path) winedebug=\(environment["WINEDEBUG"] ?? "")",
            to: logURL
        )
        try LegendaryManager.shared.launch(
            appName: appName,
            wine: wine,
            prefix: prefixURL,
            extraEnvironment: environment
        )
    }

    public func stopStore(_ store: GameStore) throws {
        let config = try loadBottleConfig(for: store)
        let engine = resolvedEngine(for: store, config: config)
        guard PathManager.shared.wineserverExecutable(engine: engine) != nil else {
            throw WineError.wineNotInstalled
        }
        try killPrefix(prefix: PathManager.shared.prefixURL(for: store), engine: engine)
    }

    public func isStoreRunning(_ store: GameStore) -> Bool {
        let prefixURL = PathManager.shared.prefixURL(for: store)
        if store == .epic {
            return PrefixRuntime.hasWineProcess(
                prefixPath: prefixURL.path,
                processLines: PrefixRuntime.processArgumentLines()
            )
        }
        let executableName = URL(fileURLWithPath: store.executablePath).lastPathComponent
        if store == .steam {
            return PrefixRuntime.isBottleSteamRunning(prefixPath: prefixURL.path, processLines: PrefixRuntime.processPIDLines())
        }
        return PrefixRuntime.isRunning(prefix: prefixURL, executableName: executableName)
    }

    public func isStoreInstalled(_ store: GameStore) -> Bool {
        if store == .epic {
            return isPrefixPresent(.epic) && LegendaryManager.shared.isBinaryInstalled()
        }
        return StoreExecutable.resolve(in: PathManager.shared.prefixURL(for: store), store: store) != nil
    }

    public func isPrefixPresent(_ store: GameStore) -> Bool {
        let prefix = PathManager.shared.prefixURL(for: store)
        return fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
            || fileManager.fileExists(atPath: prefix.appendingPathComponent("drive_c").path)
    }

    public func resolvedExecutable(for store: GameStore) -> URL? {
        StoreExecutable.resolve(in: PathManager.shared.prefixURL(for: store), store: store)
    }

    public func deletePrefix(for store: GameStore) throws {
        try? stopStore(store)

        let bottleURL = PathManager.shared.bottleURL(for: store)

        if fileManager.fileExists(atPath: bottleURL.path) {
            try fileManager.removeItem(at: bottleURL)
        }
    }

    public func launchExecutable(at path: String, config: BottleConfiguration) throws {
        let engine = resolvedEngine(for: .steam, config: config)
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }

        let prefixURL = PathManager.shared.bottlesURL.appendingPathComponent("custom").appendingPathComponent("prefix")

        if !fileManager.fileExists(atPath: prefixURL.path) {
            try fileManager.createDirectory(at: prefixURL, withIntermediateDirectories: true)
        }

        var environment = buildEnvironment(for: .steam, config: config)
        environment["WINEPREFIX"] = prefixURL.path

        try launchDetached(
            executable: wineExecutable,
            arguments: [path],
            environment: environment,
            workingDirectory: nil,
            logURL: PathManager.shared.bottlesURL.appendingPathComponent("custom.log")
        )
    }

    public func loadBottleConfig(for store: GameStore) throws -> BottleConfiguration {
        let configURL = PathManager.shared.bottleConfigURL(for: store)

        guard fileManager.fileExists(atPath: configURL.path) else {
            return BottleConfiguration()
        }

        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(BottleConfiguration.self, from: data)
    }

    public func saveBottleConfig(_ config: BottleConfiguration, for store: GameStore) throws {
        let configURL = PathManager.shared.bottleConfigURL(for: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL)
    }

    private func migrateSteamBottleIfNeeded(
        prefixURL: URL,
        engine: WineEngine,
        config: BottleConfiguration
    ) throws {
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else {
            throw WineError.wineNotInstalled
        }

        let userReg = prefixURL.appendingPathComponent("user.reg")
        let contents = (try? String(contentsOf: userReg, encoding: .utf8)) ?? ""
        let ops = SteamBottleMigration.writes(
            userReg: contents,
            engine: engine,
            backend: graphicsBackend(config)
        )
        guard !ops.isEmpty else { return }

        var environment = buildEnvironment(for: .steam, config: config)
        // Same sync mode (esync/msync) as the launch: a wineserver started here
        // without WINEMSYNC makes steam.exe fail with "msync_init Failed bootstrap_look_up".
        for key in StoreLaunchRecipe.syncEnvironmentKeys {
            if let value = StoreLaunchRecipe.syncEnvironment(for: .steam)[key] { environment[key] = value }
        }
        environment["WINEPREFIX"] = prefixURL.path
        try apply(ops, wineExecutable: wineExecutable, environment: environment)
        // Let that wineserver exit so the launch starts a fresh one with its own environment.
        waitForWineserver(prefix: prefixURL, engine: engine)
    }

    private func waitForWineserver(prefix: URL, engine: WineEngine, timeout: TimeInterval = 15) {
        guard let wineserverExecutable = PathManager.shared.wineserverExecutable(engine: engine) else { return }
        let process = Process()
        process.executableURL = wineserverExecutable
        process.arguments = ["-w"]
        process.environment = ["WINEPREFIX": prefix.path]
        guard (try? process.run()) != nil else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        if process.isRunning { process.terminate() }
    }

    private func configureLauncherBottle(
        for store: GameStore,
        config: BottleConfiguration,
        engine: WineEngine
    ) throws {
        guard store == .epic || store == .gog else { return }
        guard let wineExecutable = PathManager.shared.wineExecutable(engine: engine) else { return }
        let prefixURL = PathManager.shared.prefixURL(for: store)
        var environment = buildEnvironment(for: store, config: config)
        environment["WINEPREFIX"] = prefixURL.path
        let backend = graphicsBackend(config)
        var ops = DllOverridePolicy.registryWrites(
            engine: engine,
            backend: backend,
            store: store
        )
        if store == .epic {
            let userReg = (try? String(
                contentsOf: prefixURL.appendingPathComponent("user.reg"),
                encoding: .utf8
            )) ?? ""
            ops.append(contentsOf: EpicVulkanPolicy.leftoverDisabledVulkanWrites(
                userReg: userReg,
                backend: backend
            ))
        }
        try apply(ops, wineExecutable: wineExecutable, environment: environment)
        if store == .epic, backend == .dxvk {
            try ensureDXVKPlacement(prefixURL: prefixURL)
        }
        if store == .epic {
            try ensureDXMTPlacement(engine: engine, config: config, prefixURL: prefixURL, store: store)
        }
    }

    private func applyEpicGraphics(config: BottleConfiguration) throws {
        let engine = resolvedEngine(for: .epic, config: config)
        try configureLauncherBottle(for: .epic, config: config, engine: engine)
    }

    private func ensureEngineInstalled(_ engine: WineEngine) async throws {
        if EngineManager.shared.isEngineInstalled(engine) { return }
        try await EngineManager.shared.downloadEngine(engine) { _ in }
    }

    private func ensureDXVKPlacement(prefixURL: URL) throws {
        guard let overlay = PathManager.shared.dxvkOverlay() else { return }
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32")
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        for name in ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"] {
            guard let source = overlay.windowsDLL(name) else { continue }
            let dest = system32.appendingPathComponent(name)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: source, to: dest)
        }
    }

    private func ensureDXMTPlacement(
        engine: WineEngine,
        config: BottleConfiguration,
        prefixURL: URL,
        store: GameStore
    ) throws {
        guard StoreRecipe.allowsNativeGraphics(store) else { return }
        guard let layout = PathManager.shared.engineLayout(for: engine) else { return }
        // Automatic: byte-compatible with main — bundledDXMTOverlay() ?? dxmtOverlay()
        // (flat engines/dxmt first). Never force AppConfiguration.defaultDXMTVersion ("v0.80")
        // into the prefix when the bottle still says Automatic.
        let overlay: OverlayLayout?
        if SettingInheritance.isAutomatic(config.dxmtVersion) {
            overlay = layout.bundledDXMTOverlay() ?? PathManager.shared.dxmtOverlay()
        } else {
            let tag = StoreRecipe.effectiveDXMTVersion(config, global: appConfiguration()).value
            let versioned = OverlayLayout.resolve(
                installRoot: DXMTVersionManager.shared.installURL(for: tag),
                fileManager: fileManager
            )
            overlay = versioned ?? layout.bundledDXMTOverlay() ?? PathManager.shared.dxmtOverlay()
        }
        guard let overlay else { return }

        if engine.supportsDXMT {
            try DXMTUnixLib.installIfNeeded(overlay: overlay, engine: layout)
        }

        guard DllOverridePolicy.usesNativeDXMT(
            engine: engine,
            backend: graphicsBackend(config),
            store: store
        ) else {
            return
        }

        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32")
        let syswow64 = prefixURL.appendingPathComponent("drive_c/windows/syswow64")
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: syswow64, withIntermediateDirectories: true)

        for pair in DXMTWindowsDLLs.copyPlan(overlay: overlay, system32: system32, syswow64: syswow64) {
            guard fileManager.fileExists(atPath: pair.from.path) else { continue }
            if fileManager.fileExists(atPath: pair.to.path) {
                try fileManager.removeItem(at: pair.to)
            }
            try fileManager.copyItem(at: pair.from, to: pair.to)
        }
    }

    private func apply(
        _ ops: [WineRegOp],
        wineExecutable: URL,
        environment: [String: String]
    ) throws {
        for op in ops {
            let process = Process()
            process.executableURL = wineExecutable
            process.arguments = op.argv
            process.environment = environment
            try process.run()
            process.waitUntilExit()
        }
    }

    private func killPrefix(prefix: URL, engine: WineEngine) throws {
        guard let wineserverExecutable = PathManager.shared.wineserverExecutable(engine: engine) else {
            return
        }
        let stopProcess = Process()
        stopProcess.executableURL = wineserverExecutable
        stopProcess.arguments = ["-k"]
        stopProcess.environment = ["WINEPREFIX": prefix.path]
        try stopProcess.run()
        stopProcess.waitUntilExit()
    }

    private func appendLaunchLog(_ line: String, to logURL: URL) {
        try? fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        CappedLogWriter.shared(for: logURL).append(line: line)
    }

    private func launchDetached(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        logURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let spawnPath: String
        let argv: [String]
        let spawnCwd: String?
#if os(macOS)
        spawnPath = executable.path
        argv = [executable.path] + arguments
        spawnCwd = workingDirectory
#else
        spawnPath = "/bin/sh"
        let quotedExec = Self.shellQuote(executable.path)
        let quotedArgs = arguments.map(Self.shellQuote).joined(separator: " ")
        var script = "exec \(quotedExec) \(quotedArgs)"
        if let workingDirectory {
            script = "cd \(Self.shellQuote(workingDirectory)) && \(script)"
        }
        argv = ["/bin/sh", "-c", script]
        spawnCwd = nil
#endif
        // Child stdout/stderr go through a pipe into the capped log writer, never
        // straight into the file: a Wine error loop can't fill the disk.
        let writer = CappedLogWriter.shared(for: logURL)
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw WineError.launchFailed(errno) }
        // If Vermut quits, the child's writes get EPIPE instead of SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let pid: pid_t
        do {
            pid = try posixSpawnSetSID(
                path: spawnPath,
                argv: argv,
                environment: environment,
                outputFD: fds[1],
                closeFD: fds[0],
                workingDirectory: spawnCwd
            )
            close(fds[1])
            writer.pump(readFD: fds[0])
        } catch {
            close(fds[0]); close(fds[1])
            appendLaunchLog(
                "Vermut: spawn failed status=\(error.localizedDescription) exe=\(executable.path) cwd=\(workingDirectory ?? "")",
                to: logURL
            )
            throw error
        }

        appendLaunchLog(
            "Vermut: spawn pid=\(pid) exe=\(executable.path) cwd=\(workingDirectory ?? "") argv=\(arguments.joined(separator: " "))",
            to: logURL
        )

        var exitStatus: Int32 = 0
        usleep(100_000)
        let waited = waitpid(pid, &exitStatus, WNOHANG)
        if waited == pid {
            let exitCode = (exitStatus >> 8) & 0xff
            appendLaunchLog(
                "Vermut: spawn pid=\(pid) exited immediately wait_status=\(exitStatus) exit=\(exitCode) wine=\(executable.path) prefix=\(environment["WINEPREFIX"] ?? "") cwd=\(workingDirectory ?? "")",
                to: logURL
            )
            appendSpawnStderr(from: logURL)
            // Surface the failure so the card shows an error with Retry instead of "Installed".
            throw WineError.launchFailed(exitCode)
        } else if waited < 0 {
            appendLaunchLog(
                "Vermut: spawn pid=\(pid) waitpid errno=\(errno)",
                to: logURL
            )
        }
    }

    private func appendSpawnStderr(from logURL: URL) {
        usleep(50_000)  // let the pump drain what the child wrote before exiting
        CappedLogWriter.shared(for: logURL).flush()
        let snapshot = LogTail.read(from: logURL, maxBytes: 64 * 1024, maxLines: 200)
        let lines = snapshot.lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Vermut:") }
            .suffix(24)
        if lines.isEmpty {
            appendLaunchLog("Vermut: spawn stderr empty (log=\(logURL.path))", to: logURL)
            return
        }
        for line in lines {
            appendLaunchLog("Vermut: spawn stderr \(line)", to: logURL)
        }
    }

#if !os(macOS)
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
#endif

    /// New session via posix_spawn(SETSID). Not a Foundation Process, so the app
    /// cannot reap or signal Steam when the launcher function returns.
#if os(macOS)
    private var posixSpawnSetSIDFlag: Int16 { 0x0400 }
#else
    private var posixSpawnSetSIDFlag: Int16 { 0x80 }
#endif

    private func posixSpawnSetSID(
        path: String,
        argv: [String],
        environment: [String: String],
        outputFD: Int32,
        closeFD: Int32,
        workingDirectory: String?
    ) throws -> pid_t {
        var pid: pid_t = 0
#if os(macOS)
        var attr: posix_spawnattr_t?
        var fileActions: posix_spawn_file_actions_t?
#else
        var attr = posix_spawnattr_t()
        var fileActions = posix_spawn_file_actions_t()
#endif
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        _ = posix_spawnattr_setflags(&attr, posixSpawnSetSIDFlag)

        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        _ = posix_spawn_file_actions_addopen(
            &fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0
        )
        _ = posix_spawn_file_actions_adddup2(&fileActions, outputFD, STDOUT_FILENO)
        _ = posix_spawn_file_actions_adddup2(&fileActions, outputFD, STDERR_FILENO)
        _ = posix_spawn_file_actions_addclose(&fileActions, outputFD)
        _ = posix_spawn_file_actions_addclose(&fileActions, closeFD)
        if let workingDirectory {
#if os(macOS)
            _ = workingDirectory.withCString { cDir in
                posix_spawn_file_actions_addchdir_np(&fileActions, cDir)
            }
#endif
        }

        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgv.append(nil)
        defer { cArgv.forEach { free($0) } }
        var cEnv: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer { cEnv.forEach { free($0) } }

        let status = path.withCString { cPath in
            posix_spawn(&pid, cPath, &fileActions, &attr, cArgv, cEnv)
        }
        guard status == 0 else {
            throw WineError.launchFailed(status)
        }
        return pid
    }

    private func buildEnvironment(
        for store: GameStore,
        config: BottleConfiguration,
        wineDebug: String? = nil
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        let engine = resolvedEngine(for: store, config: config)
        if let layout = PathManager.shared.engineLayout(for: engine) {
            let bin = layout.binDir.path
            env["PATH"] = bin + ":" + (env["PATH"] ?? "")
            env["WINELOADER"] = layout.wineExecutable.path
            env["WINESERVER"] = layout.wineserverExecutable.path
            env["WINEDLLPATH"] = layout.wineLibDir.path
        }

        applyWineDebug(&env, preferred: wineDebug)
        return env
    }

    /// Sets `WINEDEBUG` from preferred level, then `VERMUT_WINEDEBUG` if present.
    private func applyWineDebug(_ env: inout [String: String], preferred: String?) {
        env["WINEDEBUG"] = preferred ?? "-all"
        if let override = ProcessInfo.processInfo.environment["VERMUT_WINEDEBUG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            env["WINEDEBUG"] = override
        }
    }

    private func graphicsBackend(_ config: BottleConfiguration) -> GraphicsBackend {
        GraphicsBackend(rawValue: config.graphicsBackend) ?? .wined3d
    }
}

public enum PrefixRuntime {
    /// True when the store exe (e.g. steam.exe) is alive for this WINEPREFIX.
    static func isRunning(prefix: URL, executableName: String) -> Bool {
        isStoreProcessRunning(
            executableName: executableName,
            prefixPath: prefix.path,
            processLines: processArgumentLines()
        )
    }

    public static func isStoreProcessRunning(
        executableName: String,
        prefixPath: String,
        processLines: [String]
    ) -> Bool {
        processLines.contains { line in
            line.contains(executableName) && line.contains(prefixPath)
        }
    }

    /// Wine hides WINEPREFIX from Windows processes' ps lines ("C:\\...\\steam.exe"),
    /// so Steam counts as running when its Windows steam.exe is up and this
    /// bottle's wine/wineserver is alive.
    public static func isBottleSteamRunning(prefixPath: String, processLines: [String]) -> Bool {
        if isStoreProcessRunning(executableName: "steam.exe", prefixPath: prefixPath, processLines: processLines) { return true }
        let steamUp = processLines.contains { line in
            let l = line.lowercased()
            return l.contains("c:\\") && l.contains("\\steam\\steam.exe")
        }
        return steamUp && hasWineProcess(prefixPath: prefixPath, processLines: processLines)
    }

    /// Any wine/wineserver process whose environment or argv names this prefix.
    public static func hasWineProcess(prefixPath: String, processLines: [String]) -> Bool {
        processLines.contains { line in
            guard line.contains(prefixPath) else { return false }
            let lower = line.lowercased()
            return lower.contains("wineserver")
                || lower.contains("/wine ")
                || lower.contains("/wine64")
                || lower.hasSuffix("/wine")
                || lower.contains("wine.exe")
                || lower.contains("wine-preloader")
        }
    }

    /// `ps …e…` includes the environment so WINEPREFIX is visible even when
    /// argv is just `steam.exe`.
    /// `ps` lines as "pid command+env".
    public static func processPIDLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axEww", "-o", "pid=,command="]
        process.standardError = FileHandle.nullDevice
        guard let data = try? ProcessPipe.runReadingStdout(process) else { return [] }
        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty } ?? []
    }

    public static func processArgumentLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        #if os(macOS)
        process.arguments = ["-axEww", "-o", "command="]
        #else
        process.arguments = ["axeww", "-o", "args="]
        #endif
        process.standardError = FileHandle.nullDevice
        do {
            // Drain stdout before waitUntilExit — see ProcessPipe.
            let data = try ProcessPipe.runReadingStdout(process)
            return String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty } ?? []
        } catch {
            return []
        }
    }
}

public enum WineError: LocalizedError {
    case wineNotInstalled
    case prefixCreationFailed
    case invalidInstallerURL
    case downloadFailed
    case executableNotFound
    case launchFailed(Int32)
    case installerTimedOut(GameStore)
    case installerFailed(GameStore, Int32)
    case cancelled

    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .wineNotInstalled:
            return "Wine is not installed"
        case .prefixCreationFailed:
            return "Failed to create Wine prefix"
        case .invalidInstallerURL:
            return "Invalid installer URL"
        case .downloadFailed:
            return "Failed to download installer"
        case .executableNotFound:
            return "Store executable not found"
        case .launchFailed(let code):
            return "Failed to launch (exit code \(code)). See the logs."
        case .cancelled:
            return "Installation cancelled"
        case .installerTimedOut(let store):
            switch store {
            case .gog:
                return "GOG Galaxy setup did not finish in time. Vermut uses the silent offline installer (/VERYSILENT). Close any leftover setup wizard and retry."
            case .epic:
                return "Epic bottle setup did not finish in time. Check Bottles → Logs, then retry."
            case .steam:
                return "The Steam installer did not finish in time. Check Bottles → Logs, then retry."
            }
        case .installerFailed(let store, let status):
            return "The \(store.rawValue) installer exited with status \(status). Check Bottles → Logs."
        }
    }
}

/// Finds GOG Galaxy's installer-spawned `/firstRun` client in one prefix.
public enum GOGFirstRun {
    public static func pids(in psLines: [String], prefixPath: String) -> [pid_t] {
        psLines.compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("GalaxyClient.exe"),
                  line.contains("/firstRun"),
                  line.contains("WINEPREFIX=\(prefixPath)") else { return nil }
            return line.split(separator: " ", maxSplits: 1).first.flatMap { pid_t($0) }
        }
    }
}
