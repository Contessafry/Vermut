import Foundation

/// One-time move of `~/Library/Application Support/CaskLauncher/` to `…/Vermut/`.
///
/// Safe: the folder is only renamed when no Wine process is using bottles in the
/// legacy tree. If a prefix is live, this launch keeps the old path and the
/// next launch retries. A failed move falls back to the legacy directory.
public enum DataDirectoryMigration: Sendable {
    public static let currentFolderName = "Vermut"
    public static let legacyFolderName = "CaskLauncher"

    public struct Outcome: Equatable, Sendable {
        public var appSupportURL: URL
        public var migrated: Bool
        public var deferred: Bool
        public var usedFallback: Bool

        public init(
            appSupportURL: URL,
            migrated: Bool = false,
            deferred: Bool = false,
            usedFallback: Bool = false
        ) {
            self.appSupportURL = appSupportURL
            self.migrated = migrated
            self.deferred = deferred
            self.usedFallback = usedFallback
        }
    }

    public static func resolve(
        applicationSupport: URL,
        fileManager: FileManager = .default,
        processLister: @escaping () -> [String] = PrefixRuntime.processArgumentLines,
        wineRunningInLegacy: ((URL) -> Bool)? = nil
    ) -> Outcome {
        let current = applicationSupport.appendingPathComponent(currentFolderName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
        let currentIsDirectory = isDirectory(current, fileManager: fileManager)
        let legacyExists = fileManager.fileExists(atPath: legacy.path)

        if currentIsDirectory, isPopulated(current, fileManager: fileManager) || !legacyExists {
            return Outcome(appSupportURL: current)
        }
        guard legacyExists else {
            return Outcome(appSupportURL: current)
        }

        let running: Bool
        if let wineRunningInLegacy {
            running = wineRunningInLegacy(legacy)
        } else {
            running = bottlesHaveWineProcess(
                bottlesURL: legacy.appendingPathComponent("bottles", isDirectory: true),
                processLister: processLister,
                fileManager: fileManager
            )
        }

        if running {
            return Outcome(appSupportURL: legacy, deferred: true)
        }

        do {
            if currentIsDirectory {
                try fileManager.removeItem(at: current)
            }
            try fileManager.moveItem(at: legacy, to: current)
            return Outcome(appSupportURL: current, migrated: true)
        } catch {
            return Outcome(appSupportURL: legacy, usedFallback: true)
        }
    }

    public static let pendingMoveHint = "Will move to Vermut on next restart"

    public static func displayPath(of url: URL, home: String, deferred: Bool) -> String {
        var path = url.path
        if path.hasPrefix(home) {
            path = "~" + String(path.dropFirst(home.count))
        }
        if deferred {
            return path + "\n" + pendingMoveHint
        }
        return path
    }

    /// True when the folder already holds bottles, engines, or a config — not
    /// an empty placeholder created while a CaskLauncher tree was still live.
    public static func isPopulated(_ url: URL, fileManager: FileManager = .default) -> Bool {
        if fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path) {
            return true
        }
        for child in ["bottles", "engines", "cache"] {
            let dir = url.appendingPathComponent(child, isDirectory: true)
            if let items = try? fileManager.contentsOfDirectory(atPath: dir.path),
               items.contains(where: { !$0.hasPrefix(".") }) {
                return true
            }
        }
        return false
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public static func bottlesHaveWineProcess(
        bottlesURL: URL,
        processLister: () -> [String],
        fileManager: FileManager = .default
    ) -> Bool {
        let processLines = processLister()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: bottlesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for directory in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let prefix = directory.appendingPathComponent("prefix", isDirectory: true)
            let paths = [prefix.path, prefix.standardizedFileURL.path]
            if paths.contains(where: { PrefixRuntime.hasWineProcess(prefixPath: $0, processLines: processLines) }) {
                return true
            }
        }
        return false
    }
}
