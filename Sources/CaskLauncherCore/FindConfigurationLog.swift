import Foundation

/// Bounded per-attempt logs for Find configuration. Never write Wine verbose into these files.
public enum FindConfigurationLog {
    /// 2 MiB per attempt + one rotated sibling. A past unbounded Wine log reached 112 GB.
    public static let defaultMaxBytes: UInt64 = 2 * 1024 * 1024

    public static func directoryURL(
        store: GameStore,
        appId: String,
        pathManager: PathManager = .shared
    ) -> URL {
        pathManager
            .bottleLogsURL(for: store)
            .appendingPathComponent("find-config", isDirectory: true)
            .appendingPathComponent(PathManager.sanitizedGameFileName(appId), isDirectory: true)
    }

    public static func url(
        store: GameStore,
        appId: String,
        attempt: Int,
        pathManager: PathManager = .shared
    ) -> URL {
        let name = String(format: "attempt-%02d.log", attempt)
        return directoryURL(store: store, appId: appId, pathManager: pathManager)
            .appendingPathComponent(name)
    }

    public static func writer(
        store: GameStore,
        appId: String,
        attempt: Int,
        maxBytes: UInt64 = defaultMaxBytes,
        pathManager: PathManager = .shared
    ) -> CappedLogWriter {
        CappedLogWriter(
            url: url(store: store, appId: appId, attempt: attempt, pathManager: pathManager),
            maxBytes: maxBytes
        )
    }

    public static func writeHeader(
        _ writer: CappedLogWriter,
        attempt: Int,
        total: Int,
        combo: FindConfigurationCombo,
        gameName: String
    ) {
        writer.append(line: "Vermut find-configuration attempt \(attempt)/\(total)")
        writer.append(line: "game=\(gameName)")
        writer.append(line: "combo=\(combo.displayLabel)")
        writer.append(line: "engine=\(combo.engine.rawValue) graphics=\(combo.graphics.compatIdentifier) overlay=\(combo.steamOverlayEnabled) launch=\(combo.launchOption.argumentString)")
        writer.append(line: "winedebug=\(WineLogLevel.errors.wineDebug) (never verbose during search)")
    }

    /// Copy a bounded tail of the store log into the attempt file (store log is already capped).
    public static func appendStoreLogTail(
        _ writer: CappedLogWriter,
        storeLogURL: URL,
        maxBytes: Int = 256 * 1024
    ) {
        let snap = LogTail.read(from: storeLogURL, maxBytes: maxBytes, maxLines: 800)
        guard !snap.lines.isEmpty else { return }
        writer.append(line: "--- store log tail (\(snap.lines.count) lines) ---")
        for line in snap.lines {
            writer.append(line: line)
        }
    }

    public static func summarizeTried(_ attempts: [FindConfigurationAttempt]) -> String {
        let lines = attempts.map { attempt in
            let status = attempt.outcome.rawValue
            let detail = attempt.detail.isEmpty ? "" : " — \(attempt.detail)"
            return "\(attempt.index). \(attempt.combo.displayLabel) (\(status)\(detail))"
        }
        return lines.joined(separator: "\n")
    }
}
