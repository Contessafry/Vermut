import Foundation

/// Hard exclusions and whitelist rules for the Vermut uninstaller.
/// Every path is resolved with `resolvingSymlinksInPath` before removal, except
/// Wine `dosdevices/z:` links which are never followed (the link is removed, not the target).
public enum UninstallPathPolicy: Sendable {
    public static let bundleIdentifier = "com.opensource.vermut"

    /// Paths that must never be touched, even if a calculated path points there.
    public static func hardExclusionRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        return [
            appSupport.appendingPathComponent("Steam", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true),
            appSupport.appendingPathComponent("GOG.com", isDirectory: true),
            URL(fileURLWithPath: "/Applications/GOG Galaxy.app", isDirectory: true),
            appSupport.appendingPathComponent("Epic", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Epic Games Launcher.app", isDirectory: true),
            appSupport.appendingPathComponent("CrossOver", isDirectory: true),
            appSupport.appendingPathComponent("Whisky", isDirectory: true),
            appSupport.appendingPathComponent("com.isaacmarovitz.Whisky", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
            URL(fileURLWithPath: "/usr/local", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app", isDirectory: true),
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/Users", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
        ]
    }

    /// Allowed roots for trash operations (Vermut data + app + com.opensource.vermut* Library paths).
    public static func allowedPrefixes(
        appSupport: URL,
        appBundle: URL?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        includeLegacyCaskLauncher: Bool = true
    ) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var prefixes: [URL] = [
            appSupport,
            library.appendingPathComponent("Logs/Vermut", isDirectory: true),
            library.appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).plist"),
            library.appendingPathComponent("Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true),
            library.appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
            library.appendingPathComponent("HTTPStorages", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true),
        ]
        if includeLegacyCaskLauncher {
            prefixes.append(
                library.appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent(DataDirectoryMigration.legacyFolderName, isDirectory: true)
            )
        }
        if let appBundle {
            prefixes.append(appBundle)
        }
        return prefixes
    }

    /// True when `path` is under a Wine `dosdevices` folder and named `z:` (or `z`).
    public static func isWineZDriveSymlink(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        guard name == "z:" || name == "z" else { return false }
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        return parent == "dosdevices"
    }

    /// Whether the enumerator / size walker should descend into this URL.
    /// Wine `z:` links point at `/` and must never be followed.
    public static func shouldDescend(into url: URL, fileManager: FileManager = .default) -> Bool {
        if isWineZDriveSymlink(url) { return false }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            // Other symlinks inside a bottle: do not follow targets for size/removal recursion.
            return false
        }
        return true
    }

    /// Resolves symlinks unless this is a Wine `z:` link (kept as-is for whitelist checks of the link itself).
    public static func pathForSafetyCheck(_ url: URL) -> URL {
        if isWineZDriveSymlink(url) { return url.standardizedFileURL }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func isHardExcluded(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let resolved = pathForSafetyCheck(url)
        // Exact `/` is always excluded as a removal target.
        if resolved.path == "/" { return true }
        for root in hardExclusionRoots(home: home) {
            if isURL(resolved, under: root) {
                // Vermut's own copy under Application Support/Vermut/D3DMetal is not GPTK system.
                if root.lastPathComponent == "Game Porting Toolkit.app" { return true }
                if root.path == "/" || root.path == "/Users" || root.path == "/Library"
                    || root.path == "/Applications" || root.path == "/System" {
                    // Only treat exact roots as excluded when the candidate *is* that root.
                    if resolved.standardizedFileURL.path == root.standardizedFileURL.path {
                        return true
                    }
                    continue
                }
                return true
            }
        }
        return false
    }

    public static func isWithinWhitelist(
        _ url: URL,
        allowedPrefixes: [URL]
    ) -> Bool {
        let candidate = pathForSafetyCheck(url)
        if candidate.path == "/" { return false }
        for prefix in allowedPrefixes {
            if isURL(candidate, under: prefix) { return true }
            // HTTPStorages may be `com.opensource.vermut*` with suffixes.
            let name = candidate.lastPathComponent
            if prefix.lastPathComponent == bundleIdentifier,
               prefix.deletingLastPathComponent().lastPathComponent == "HTTPStorages",
               name.hasPrefix(bundleIdentifier) {
                return true
            }
        }
        return false
    }

    /// Validates a path for trash. Returns `nil` when safe, otherwise a skip reason.
    public static func validateForRemoval(
        _ url: URL,
        allowedPrefixes: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        if isWineZDriveSymlink(url) {
            // Removing the link itself is safe; never follow.
            return nil
        }
        if isHardExcluded(url, home: home) {
            return "Skipped for safety: path is outside Vermut's folder."
        }
        if !isWithinWhitelist(url, allowedPrefixes: allowedPrefixes) {
            return "Skipped for safety: path is outside Vermut's folder."
        }
        return nil
    }

    public static func isURL(_ url: URL, under root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if path == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix)
    }

    /// Library preference / cache / state URLs for `com.opensource.vermut`.
    public static func preferenceRelatedURLs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var urls: [URL] = [
            library.appendingPathComponent("Preferences/\(bundleIdentifier).plist"),
            library.appendingPathComponent(
                "Saved Application State/\(bundleIdentifier).savedState",
                isDirectory: true
            ),
            library.appendingPathComponent("Caches/\(bundleIdentifier)", isDirectory: true),
        ]
        let httpRoot = library.appendingPathComponent("HTTPStorages", isDirectory: true)
        if let kids = try? fileManager.contentsOfDirectory(
            at: httpRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            urls.append(contentsOf: kids.filter { $0.lastPathComponent.hasPrefix(bundleIdentifier) })
        } else {
            urls.append(httpRoot.appendingPathComponent(bundleIdentifier, isDirectory: true))
        }
        return urls
    }

    public static func systemLogsURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent("Library/Logs/Vermut", isDirectory: true)
    }

    public static func legacyCaskLauncherURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/\(DataDirectoryMigration.legacyFolderName)",
            isDirectory: true
        )
    }
}
