import Foundation

/// Recorded / probed Gcenx Wine versions and whether an update can be offered.
public enum WineEngineVersion {
    public static let recordedFileName = ".vermut-version"

    public static func readRecorded(
        fromEngineRoot root: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let url = root.appendingPathComponent(recordedFileName)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseVersionToken(raw)
    }

    public static func writeRecorded(
        _ version: String,
        toEngineRoot root: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = root.appendingPathComponent(recordedFileName)
        try version.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Reads `CFBundleShortVersionString` / `CFBundleVersion` from a Gcenx `.app` under the engine root.
    public static func probeBundleVersion(
        fromEngineRoot root: URL,
        fileManager: FileManager = .default
    ) -> String? {
        for plist in infoPlistURLs(under: root, fileManager: fileManager) {
            if let version = versionFromInfoPlist(plist, fileManager: fileManager) {
                return version
            }
        }
        return nil
    }

    /// Recorded version, else a one-shot probe of the bundle (optionally persisted).
    public static func resolved(
        fromEngineRoot root: URL,
        persistProbe: Bool = false,
        fileManager: FileManager = .default
    ) -> String? {
        if let recorded = readRecorded(fromEngineRoot: root, fileManager: fileManager) {
            return recorded
        }
        guard let probed = probeBundleVersion(fromEngineRoot: root, fileManager: fileManager) else {
            return nil
        }
        if persistProbe {
            try? writeRecorded(probed, toEngineRoot: root, fileManager: fileManager)
        }
        return probed
    }

    /// Installed engines show only a real version; available engines show catalog / offline fallback.
    public static func displayVersion(
        isInstalled: Bool,
        installedVersion: String?,
        catalogVersion: String?,
        fallbackVersion: String
    ) -> String? {
        if isInstalled {
            return nonempty(installedVersion)
        }
        if let catalog = nonempty(catalogVersion) { return catalog }
        return nonempty(fallbackVersion)
    }

    /// Grapple Wine is not updated here. An installed Gcenx engine with no recorded version
    /// is treated as older than any known catalog tag so the user can refresh it.
    public static func isUpdateAvailable(
        engine: WineEngine,
        isInstalled: Bool,
        installedVersion: String?,
        catalogVersion: String?
    ) -> Bool {
        guard engine != .grappleWine, isInstalled else { return false }
        guard let catalog = nonempty(catalogVersion) else { return false }
        guard let installed = nonempty(installedVersion) else { return true }
        return ComponentVersion.compare(catalog, installed) == .orderedDescending
    }

    public static func canApplyUpdate(isInUse: Bool, isBusy: Bool) -> Bool {
        !isInUse && !isBusy
    }

    public static func parseVersionToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = ComponentVersion.normalize(trimmed)
        if looksLikeVersion(normalized) { return normalized }
        if looksLikeVersion(trimmed) { return trimmed }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()[],;"))
        for token in trimmed.components(separatedBy: separators).reversed() {
            let piece = ComponentVersion.normalize(token)
            if looksLikeVersion(piece) { return piece }
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func looksLikeVersion(_ raw: String) -> Bool {
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty, !compact.contains(where: \.isWhitespace) else { return false }
        let parts = compact.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isNumber else { return false }
            return part.allSatisfy { $0.isNumber || $0.isLetter || $0 == "-" }
        }
    }

    private static func infoPlistURLs(under root: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = [
            root.appendingPathComponent("Contents/Info.plist")
        ]
        guard let items = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return urls.filter { fileManager.fileExists(atPath: $0.path) }
        }
        for item in items where item.pathExtension == "app" {
            urls.append(item.appendingPathComponent("Contents/Info.plist"))
        }
        return urls.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func versionFromInfoPlist(_ url: URL, fileManager: FileManager) -> String? {
        guard let data = fileManager.contents(atPath: url.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        let raw = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        guard let raw else { return nil }
        return parseVersionToken(raw)
    }
}

/// Whether a Wine engine is currently attached to a running bottle.
public enum WineEngineUsage {
    public static func isInUse(
        _ engine: WineEngine,
        runningStoreEngines: [WineEngine],
        runningCustomEngines: [WineEngine]
    ) -> Bool {
        runningStoreEngines.contains(engine) || runningCustomEngines.contains(engine)
    }
}
