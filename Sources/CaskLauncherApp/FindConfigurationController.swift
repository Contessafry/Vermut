import Foundation
import AppKit
import Darwin
import CaskLauncherCore

enum FindConfigurationPhase: Equatable {
    case idle
    case running
    case awaitingConfirmation
    case finished
}

@MainActor
final class FindConfigurationController: ObservableObject {
    @Published var phase: FindConfigurationPhase = .idle
    @Published var attempts: [FindConfigurationAttempt] = []
    @Published var currentIndex = 0
    @Published var total = 0
    @Published var currentCombo: FindConfigurationCombo?
    @Published var aliveThreshold: TimeInterval = FindConfigurationSettings.default.aliveThreshold
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var confirmedCombo: FindConfigurationCombo?
    @Published var offerCompatReport = false

    private var searchTask: Task<Void, Never>?
    private var stopRequested = false
    private var plan: [FindConfigurationCombo] = []
    private(set) var game: InstalledGame?

    var isRunning: Bool { phase == .running || phase == .awaitingConfirmation }

    var progressLabel: String {
        guard total > 0 else { return "" }
        let n = min(max(currentIndex, 1), total)
        return String(localized: "Attempt \(n) of \(total)", comment: "Find configuration progress")
    }

    func prepare(game: InstalledGame, appState: AppState, d3dMetalInstalled: Bool) {
        self.game = game
        var engines = Set(WineEngine.allCases.filter { EngineManager.shared.isEngineInstalled($0) })
        engines.insert(.grappleWine)
        let context = FindConfigurationContext(
            store: game.store,
            installedEngines: engines,
            d3dMetalInstalled: d3dMetalInstalled,
            compatibility: appState.getCompatibility(for: game)
        )
        plan = FindConfigurationPlanner.plan(context: context)
        total = plan.count
        attempts = []
        currentIndex = 0
        currentCombo = nil
        confirmedCombo = nil
        offerCompatReport = false
        errorMessage = nil
        statusMessage = plan.isEmpty
            ? String(localized: "Nothing to try — install an engine or D3DMetal first.", comment: "Find configuration empty plan")
            : String(localized: "Will try \(plan.count) configurations.", comment: "Find configuration plan size")
        phase = .idle
    }

    func start(appState: AppState) {
        guard let game, !plan.isEmpty else { return }
        stopRequested = false
        phase = .running
        appState.isFindConfigurationActive = true
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.run(appState: appState, game: game)
        }
    }

    func stop(appState: AppState) {
        stopRequested = true
        searchTask?.cancel()
        if let game, let current = currentCombo {
            appState.stopFindConfigurationAttempt(game: game, next: nil, current: current)
        }
        if phase == .running {
            phase = .finished
            statusMessage = String(localized: "Stopped.", comment: "Find configuration stopped")
        }
        appState.isFindConfigurationActive = false
    }

    func confirmWorks(appState: AppState) {
        guard let game, let combo = currentCombo else { return }
        markCurrent(outcome: .confirmed, detail: "User confirmed")
        confirmedCombo = combo
        let existing = appState.loadGameSettings(for: game)
        appState.saveGameSettings(combo.gameConfiguration(preserving: existing), for: game)
        offerCompatReport = CompatibilityService.shared.isPromptEnabled
        statusMessage = String(
            localized: "Saved this configuration for \(game.name).",
            comment: "Find configuration saved"
        )
        phase = .finished
        appState.isFindConfigurationActive = false
    }

    func rejectWorks(appState: AppState) {
        markCurrent(outcome: .rejectedByUser, detail: "User said it does not really work")
        if let game {
            _ = WineManager.shared.stopGameProcesses(
                store: game.store,
                appId: game.appId,
                installDir: game.installDir
            )
        }
        phase = .running
        searchTask = Task { [weak self] in
            await self?.continueAfterRejection(appState: appState)
        }
    }

    func openLogs(appState: AppState) {
        guard let game else {
            appState.openLogs(for: .steam)
            return
        }
        let dir = FindConfigurationLog.directoryURL(store: game.store, appId: game.appId)
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            appState.openLogs(for: game.store)
        }
    }

    func prefilledCompatReport(appState: AppState) -> CompatibilityReport? {
        guard let game, let combo = confirmedCombo else { return nil }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return CompatibilityReport(
            store: game.store.identifier,
            gameId: game.appId,
            gameName: game.name,
            vermutVersion: VermutProject.version,
            engine: combo.engine.compatIdentifier,
            graphics: combo.graphics.compatIdentifier,
            macOS: "\(version.majorVersion).\(version.minorVersion)",
            chip: chipName(),
            playMinutes: max(1, Int(aliveThreshold / 60)),
            result: CompatibilityResult.perfect.rawValue,
            note: "Found by Find configuration. Overlay \(combo.steamOverlayEnabled ? "on" : "off"). Launch options: \(combo.launchOption.displayName)."
        )
    }

    func submitCompatReport(appState: AppState) {
        guard let report = prefilledCompatReport(appState: appState),
              let url = CompatibilityService.shared.generateGitHubIssueURL(report: report)
        else { return }
        NSWorkspace.shared.open(url)
        offerCompatReport = false
    }

    var triedSummary: String {
        FindConfigurationLog.summarizeTried(attempts)
    }

    // MARK: - Search loop

    private func run(appState: AppState, game: InstalledGame) async {
        var previous: FindConfigurationCombo?
        for (offset, combo) in plan.enumerated() {
            if Task.isCancelled || stopRequested { break }
            currentIndex = offset + 1
            currentCombo = combo
            statusMessage = combo.displayLabel
            let log = FindConfigurationLog.writer(
                store: game.store,
                appId: game.appId,
                attempt: currentIndex,
                maxBytes: FindConfigurationSettings.default.attemptLogMaxBytes
            )
            FindConfigurationLog.writeHeader(
                log,
                attempt: currentIndex,
                total: total,
                combo: combo,
                gameName: game.name
            )
            var attempt = FindConfigurationAttempt(
                index: currentIndex,
                combo: combo,
                outcome: .pending,
                logURL: FindConfigurationLog.url(store: game.store, appId: game.appId, attempt: currentIndex)
            )
            if let last = attempts.last, last.index == currentIndex {
                attempts[attempts.count - 1] = attempt
            } else {
                attempts.append(attempt)
            }

            if FindGameProcess.needsStoreRestart(current: previous, next: combo), previous != nil {
                appState.stopFindConfigurationAttempt(game: game, next: combo, current: previous)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } else if previous != nil {
                _ = WineManager.shared.stopGameProcesses(
                    store: game.store,
                    appId: game.appId,
                    installDir: game.installDir
                )
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            do {
                try await appState.probeLaunch(game, combo: combo)
            } catch {
                attempt.outcome = .failed
                attempt.detail = error.localizedDescription
                replaceLast(attempt)
                log.append(line: "launch failed: \(error.localizedDescription)")
                previous = combo
                continue
            }

            let verdict = await observeAttempt(
                game: game,
                combo: combo,
                log: log
            )
            switch verdict {
            case .candidate:
                attempt.outcome = .candidate
                attempt.detail = String(
                    localized: "Looks running — does it really work?",
                    comment: "Find configuration ask user"
                )
                replaceLast(attempt)
                phase = .awaitingConfirmation
                statusMessage = String(
                    localized: "This configuration stayed up. Black screens are possible — please check the game window.",
                    comment: "Find configuration confirm hint"
                )
                return
            case .failed(let reason):
                attempt.outcome = .failed
                attempt.detail = reason
                replaceLast(attempt)
                log.append(line: "failed: \(reason)")
            case .keepWaiting:
                attempt.outcome = stopRequested ? .stopped : .failed
                attempt.detail = stopRequested ? "Stopped" : "Timed out"
                replaceLast(attempt)
            }
            previous = combo
            WineDialogDismisser.dismissVisibleDialogs()
        }

        if stopRequested {
            statusMessage = String(localized: "Stopped.", comment: "Find configuration stopped")
        } else if confirmedCombo == nil {
            statusMessage = String(
                localized: "No working configuration found. Review what was tried or open the logs.",
                comment: "Find configuration exhausted"
            )
        }
        phase = .finished
        appState.isFindConfigurationActive = false
    }

    private func continueAfterRejection(appState: AppState) async {
        guard let game, let current = currentCombo else { return }
        let remaining = plan.drop(while: { $0 != current }).dropFirst()
        var previous: FindConfigurationCombo? = current
        for (offset, combo) in remaining.enumerated() {
            if Task.isCancelled || stopRequested { break }
            currentIndex = (plan.firstIndex(of: combo) ?? offset) + 1
            currentCombo = combo
            statusMessage = combo.displayLabel
            let log = FindConfigurationLog.writer(
                store: game.store,
                appId: game.appId,
                attempt: currentIndex
            )
            FindConfigurationLog.writeHeader(
                log,
                attempt: currentIndex,
                total: total,
                combo: combo,
                gameName: game.name
            )
            attempts.append(
                FindConfigurationAttempt(
                    index: currentIndex,
                    combo: combo,
                    outcome: .pending,
                    logURL: FindConfigurationLog.url(store: game.store, appId: game.appId, attempt: currentIndex)
                )
            )
            if FindGameProcess.needsStoreRestart(current: previous, next: combo) {
                appState.stopFindConfigurationAttempt(game: game, next: combo, current: previous)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } else {
                _ = WineManager.shared.stopGameProcesses(
                    store: game.store,
                    appId: game.appId,
                    installDir: game.installDir
                )
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            do {
                try await appState.probeLaunch(game, combo: combo)
            } catch {
                replaceLast(
                    FindConfigurationAttempt(
                        index: currentIndex,
                        combo: combo,
                        outcome: .failed,
                        detail: error.localizedDescription
                    )
                )
                previous = combo
                continue
            }
            let verdict = await observeAttempt(game: game, combo: combo, log: log)
            if case .candidate = verdict {
                replaceLast(
                    FindConfigurationAttempt(
                        index: currentIndex,
                        combo: combo,
                        outcome: .candidate,
                        detail: String(localized: "Looks running — does it really work?", comment: "Find configuration ask user")
                    )
                )
                phase = .awaitingConfirmation
                statusMessage = String(
                    localized: "This configuration stayed up. Black screens are possible — please check the game window.",
                    comment: "Find configuration confirm hint"
                )
                return
            }
            if case .failed(let reason) = verdict {
                replaceLast(
                    FindConfigurationAttempt(
                        index: currentIndex,
                        combo: combo,
                        outcome: .failed,
                        detail: reason
                    )
                )
            }
            previous = combo
            WineDialogDismisser.dismissVisibleDialogs()
        }
        phase = .finished
        statusMessage = String(
            localized: "No working configuration found. Review what was tried or open the logs.",
            comment: "Find configuration exhausted"
        )
        appState.isFindConfigurationActive = false
    }

    private func observeAttempt(
        game: InstalledGame,
        combo: FindConfigurationCombo,
        log: CappedLogWriter
    ) async -> FindConfigurationVerdict {
        let started = Date()
        let threshold = FindConfigurationSettings.clampThreshold(aliveThreshold)
        var last: FindConfigurationVerdict = .keepWaiting
        while Date().timeIntervalSince(started) < threshold {
            if Task.isCancelled || stopRequested {
                return .failed("Stopped")
            }
            WineDialogDismisser.dismissVisibleDialogs()
            let snapshot = WineManager.shared.gameProcessSnapshot(
                store: game.store,
                appId: game.appId,
                installDir: game.installDir
            )
            let window = WineDialogDismisser.hasRealGameWindow(ownedBy: Set(snapshot.gamePIDs))
            let storeTail = LogTail.read(
                from: PathManager.shared.logURL(for: game.store),
                maxBytes: 128 * 1024,
                maxLines: 400
            ).text
            let attemptText = (try? String(contentsOf: log.url, encoding: .utf8)) ?? ""
            let logText = attemptText + "\n" + storeTail
            let observation = FindConfigurationObservation(
                processAlive: snapshot.isGameAlive,
                aliveSeconds: Date().timeIntervalSince(started),
                hasRealWindow: window,
                logText: logText
            )
            last = FindConfigurationSuccess.evaluate(observation, threshold: threshold)
            if last.isFailed || last == .candidate {
                FindConfigurationLog.appendStoreLogTail(
                    log,
                    storeLogURL: PathManager.shared.logURL(for: game.store)
                )
                return last
            }
            try? await Task.sleep(nanoseconds: UInt64(FindConfigurationSettings.default.pollInterval * 1_000_000_000))
        }
        FindConfigurationLog.appendStoreLogTail(
            log,
            storeLogURL: PathManager.shared.logURL(for: game.store)
        )
        return last
    }

    private func markCurrent(outcome: FindConfigurationAttemptOutcome, detail: String) {
        guard let combo = currentCombo else { return }
        if let idx = attempts.lastIndex(where: { $0.combo == combo && $0.index == currentIndex }) {
            attempts[idx].outcome = outcome
            attempts[idx].detail = detail
        }
    }

    private func replaceLast(_ attempt: FindConfigurationAttempt) {
        if attempts.last?.index == attempt.index {
            attempts[attempts.count - 1] = attempt
        } else {
            attempts.append(attempt)
        }
    }

    private func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        let brand = String(cString: machine)
        if brand.contains("Apple M") {
            let parts = brand.components(separatedBy: " ")
            for (i, part) in parts.enumerated() where part.hasPrefix("M") {
                if i + 1 < parts.count, ["Pro", "Max", "Ultra"].contains(parts[i + 1]) {
                    return part + " " + parts[i + 1]
                }
                return part
            }
        }
        return "Apple Silicon"
    }
}
