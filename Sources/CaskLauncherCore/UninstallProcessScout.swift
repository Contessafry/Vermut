import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A process that must be quit before uninstall can continue.
public struct UninstallRunningProcess: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case wineApp
        case download
    }

    public enum Status: String, Sendable, Equatable {
        case running
        case willCancel
        case didNotQuit
    }

    public var id: String { "\(kind.rawValue)-\(pid)-\(name)" }
    public var name: String
    public var detail: String
    public var pid: pid_t
    public var bottleLabel: String
    public var prefixPath: String?
    public var kind: Kind
    public var status: Status

    public init(
        name: String,
        detail: String,
        pid: pid_t,
        bottleLabel: String,
        prefixPath: String? = nil,
        kind: Kind = .wineApp,
        status: Status = .running
    ) {
        self.name = name
        self.detail = detail
        self.pid = pid
        self.bottleLabel = bottleLabel
        self.prefixPath = prefixPath
        self.kind = kind
        self.status = status
    }
}

/// Detects Vermut-managed Wine / download activity for the uninstall flow.
/// Soft quit uses `wineserver -k` only; force-kill requires a second explicit consent.
public enum UninstallProcessScout {
    public static let softQuitTimeout: TimeInterval = 15

    public struct DownloadStub: Sendable, Equatable {
        public var name: String
        public var detail: String

        public init(name: String, detail: String = "Downloads queue") {
            self.name = name
            self.detail = detail
        }
    }

    /// Lists Vermut Wine processes for the given bottle prefixes (never native Steam/GOG/Epic).
    public static func discoverWineProcesses(
        prefixes: [String],
        bottleLabelForPrefix: (String) -> String = { $0 },
        rows: [PrefixProcessTerminator.ProcessRow]? = nil,
        enginesRoot: String = PathManager.shared.enginesURL.path,
        bottlesRoot: String = PathManager.shared.bottlesURL.path,
        executablePathProvider: (pid_t) -> String? = { PrefixProcessTerminator.executablePath(for: $0) },
        openPathsProvider: (pid_t) -> [String] = { PrefixProcessTerminator.openFilePaths(for: $0) },
        currentPID: pid_t = getpid()
    ) -> [UninstallRunningProcess] {
        guard !prefixes.isEmpty else { return [] }
        let resolvedRows = rows ?? PrefixProcessTerminator.processRows()
        let pids = PrefixProcessTerminator.snapshotPrefixPIDs(
            owningPrefixes: prefixes,
            rows: resolvedRows,
            enginesRoot: enginesRoot,
            bottlesRoot: bottlesRoot,
            executablePathProvider: executablePathProvider,
            openPathsProvider: openPathsProvider,
            currentPID: currentPID
        )
        let byPID = Dictionary(uniqueKeysWithValues: resolvedRows.map { ($0.pid, $0) })
        var result: [UninstallRunningProcess] = []
        for pid in pids.sorted() {
            let command = byPID[pid]?.command ?? ""
            let name = displayName(for: command, pid: pid)
            let prefix = prefixes.first(where: { command.contains($0) }) ?? prefixes.first
            let label = prefix.map(bottleLabelForPrefix) ?? "Bottle"
            let detail = "\(label) · PID \(pid)"
            result.append(
                UninstallRunningProcess(
                    name: name,
                    detail: detail,
                    pid: pid,
                    bottleLabel: label,
                    prefixPath: prefix,
                    kind: .wineApp,
                    status: .running
                )
            )
        }
        return result
    }

    public static func downloadPlaceholders(_ downloads: [DownloadStub]) -> [UninstallRunningProcess] {
        downloads.enumerated().map { index, item in
            UninstallRunningProcess(
                name: item.name,
                detail: item.detail,
                pid: pid_t(-1 - index),
                bottleLabel: item.detail,
                prefixPath: nil,
                kind: .download,
                status: .willCancel
            )
        }
    }

    /// Ordered quit: `wineserver -k` per prefix with a 15s timeout. Never SIGKILL.
    @discardableResult
    public static func softQuit(
        prefixes: [String],
        engineForPrefix: (String) -> WineEngine? = { _ in WineEngine.defaultEngine },
        wineserverForEngine: (WineEngine) -> URL? = { PathManager.shared.wineserverExecutable(engine: $0) },
        timeout: TimeInterval = softQuitTimeout,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        wineserverRunner: @escaping @Sendable (URL, String, TimeInterval) -> Void = {
            wineserver, prefix, timeout in
            PrefixProcessTerminator.runWineserverKill(
                wineserver: wineserver,
                prefix: prefix,
                timeout: timeout
            )
        },
        now: () -> Date = { Date() }
    ) -> Void {
        let deadline = now().addingTimeInterval(timeout)
        let jobs: [(URL, String)] = prefixes.compactMap { prefix in
            let engine = engineForPrefix(prefix) ?? .defaultEngine
            guard let wineserver = wineserverForEngine(engine) else {
                return nil
            }
            return (wineserver, prefix)
        }
        guard !jobs.isEmpty else { return }
        let perTimeout = min(timeout, max(0.5, timeout / Double(jobs.count)))
        let group = DispatchGroup()
        for (wineserver, prefix) in jobs {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                wineserverRunner(wineserver, prefix, perTimeout)
            }
        }
        let remaining = max(0.1, deadline.timeIntervalSince(now()))
        _ = group.wait(timeout: .now() + remaining)
        // Brief settle so discovery sees exits.
        let settle = min(0.35, max(0, deadline.timeIntervalSince(now())))
        if settle > 0 { sleeper(settle) }
    }

    /// Force-quit after a second explicit user consent. SIGTERM then SIGKILL.
    @discardableResult
    public static func forceQuit(
        pids: [pid_t],
        termGraceSeconds: TimeInterval = 0.75,
        killGraceSeconds: TimeInterval = 0.35,
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        signalSender: (pid_t, Int32) -> Int32 = { kill($0, $1) }
    ) -> [pid_t] {
        let targets = pids.filter { $0 > 1 }
        for pid in targets {
            _ = signalSender(pid, SIGTERM)
        }
        sleeper(termGraceSeconds)
        var leftover: [pid_t] = []
        for pid in targets {
            if signalSender(pid, 0) == 0 {
                _ = signalSender(pid, SIGKILL)
                leftover.append(pid)
            }
        }
        sleeper(killGraceSeconds)
        return leftover.filter { signalSender($0, 0) == 0 }
    }

    public static func displayName(for command: String, pid: pid_t) -> String {
        let lower = command.lowercased()
        if SteamSetupEvaluator.isBottleSteamCommand(command) || lower.contains("steam.exe") {
            return "Steam (Windows)"
        }
        if lower.contains("epicgameslauncher") || lower.contains("epic games") {
            return "Epic Games (Windows)"
        }
        if lower.contains("galaxyclient") || lower.contains("gog galaxy") {
            return "GOG Galaxy (Windows)"
        }
        if lower.contains("wineserver") {
            return "Wine Server"
        }
        // Best-effort: last path component of a .exe
        if let exe = command.split(whereSeparator: { $0.isWhitespace }).last(where: {
            $0.lowercased().contains(".exe")
        }) {
            let base = String(exe).split(separator: "\\").last
                ?? String(exe).split(separator: "/").last
                ?? exe
            let cleaned = String(base).replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive)
            if !cleaned.isEmpty { return cleaned }
        }
        return "Wine process \(pid)"
    }

    public static func bottleLabel(forPrefix prefixPath: String) -> String {
        let url = URL(fileURLWithPath: prefixPath)
        // …/bottles/<id>/prefix
        let bottleFolder = url.deletingLastPathComponent().lastPathComponent
        if let store = GameStore.allCases.first(where: { $0.identifier == bottleFolder }) {
            return store == .epic ? "Epic Games bottle" : "\(store.rawValue) bottle"
        }
        if let custom = (try? CustomBottleStore.shared.load())?.first(where: {
            $0.id.uuidString == bottleFolder
        }) {
            return custom.name
        }
        return "\(bottleFolder) bottle"
    }
}
