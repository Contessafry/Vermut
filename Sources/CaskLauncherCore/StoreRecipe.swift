import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Per-store bottle policy. Steam and Epic pick DXMT/DXVK; GOG stays on WineD3D.
/// Grapple-wine has no Vulkan loader, so DXVK bottles use Wine Staging.
public enum StoreRecipe {
    /// Reserved for stores that are hidden from first-setup. GOG is available
    /// with the WineD3D + Qt software recipe in `GOGRecipe`.
    public static func isComingSoon(_ store: GameStore) -> Bool {
        switch store {
        case .steam, .epic, .gog:
            return false
        }
    }

    /// Drops "Coming soon" stores from a first-setup selection.
    public static func selectableStores(_ selection: Set<GameStore>) -> Set<GameStore> {
        selection.filter { !isComingSoon($0) }
    }

    public static func allowsNativeGraphics(_ store: GameStore) -> Bool {
        store == .steam || store == .epic
    }

    public static func bottleConfiguration(
        from app: AppConfiguration,
        for store: GameStore
    ) -> BottleConfiguration {
        // New bottles inherit Settings via Automatic; effective values resolve at launch.
        switch store {
        case .steam:
            return BottleConfiguration(
                engine: SettingInheritance.automatic,
                graphicsBackend: app.defaultGraphicsBackend,
                dxmtVersion: SettingInheritance.automatic,
                enableHiDPI: false,
                windowsVersion: "win10"
            )
        case .epic:
            return normalized(
                BottleConfiguration(
                    engine: SettingInheritance.automatic,
                    graphicsBackend: app.defaultGraphicsBackend,
                    dxmtVersion: SettingInheritance.automatic,
                    // Keep err+all so DXVK / Win64 faults still show (matches prior Epic default).
                    logLevel: WineLogLevel.errors.rawValue,
                    enableHiDPI: false,
                    windowsVersion: "win10"
                ),
                for: .epic,
                global: app
            )
        case .gog:
            return BottleConfiguration(
                engine: GOGRecipe.recommendedEngine.rawValue,
                graphicsBackend: GraphicsBackend.wined3d.rawValue,
                dxmtVersion: SettingInheritance.automatic,
                enableHiDPI: false,
                windowsVersion: "win10"
            )
        }
    }

    public static func normalized(
        _ config: BottleConfiguration,
        for store: GameStore,
        global: AppConfiguration? = nil
    ) -> BottleConfiguration {
        var config = config
        let app = global ?? ((try? ConfigurationManager.shared.loadConfiguration()) ?? AppConfiguration())
        if store == .epic {
            config.windowsVersion = "win10"
            config.enableHiDPI = false
            let backend = GraphicsBackend(rawValue: config.graphicsBackend) ?? .dxmt
            let inherited = SettingInheritance.resolveEngine(
                bottle: config.engine,
                global: app.defaultEngine
            )
            let applied = EngineGraphicsPolicy.apply(inherited: inherited, backend: backend)
            if applied.forcedForDXVK {
                config.engine = applied.engine.value.rawValue
            }
        }
        if store == .gog {
            config.graphicsBackend = GraphicsBackend.wined3d.rawValue
            config.windowsVersion = "win10"
            config.enableHiDPI = false
        }
        if store == .steam {
            config.enableHiDPI = false
            config.windowsVersion = "win10"
        }
        return config
    }

    /// Effective Wine engine for a bottle (and optional game), honouring Automatic → Settings.
    public static func effectiveEngine(
        _ config: BottleConfiguration,
        global: AppConfiguration,
        game: GameConfiguration? = nil
    ) -> EffectiveSetting<WineEngine> {
        SettingInheritance.resolveEngine(
            game: game?.engine,
            bottle: config.engine,
            global: global.defaultEngine
        )
    }

    public static func effectiveGraphics(
        _ config: BottleConfiguration,
        global: AppConfiguration,
        game: GameConfiguration? = nil
    ) -> EffectiveSetting<GraphicsBackend> {
        SettingInheritance.resolveGraphics(
            game: game?.graphicsBackend,
            bottle: config.graphicsBackend,
            global: global.defaultGraphicsBackend
        )
    }

    public static func effectiveDXMTVersion(
        _ config: BottleConfiguration,
        global: AppConfiguration,
        game: GameConfiguration? = nil
    ) -> EffectiveSetting<String> {
        SettingInheritance.resolveDXMTVersion(
            game: game?.dxmtVersion,
            bottle: config.dxmtVersion,
            global: global.defaultDXMTVersion
        )
    }

    public static func effectiveLogLevel(
        _ config: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore,
        game: GameConfiguration? = nil
    ) -> EffectiveSetting<WineLogLevel> {
        SettingInheritance.resolveLogLevel(
            game: game?.logLevel,
            bottle: config.logLevel,
            global: global.defaultLogLevel,
            storeDefault: WineLogLevel.storeDefault(for: store)
        )
    }

    /// Full Settings → bottle → game resolution for launching one title.
    public static func resolveLaunchSettings(
        game: GameConfiguration?,
        bottle: BottleConfiguration,
        global: AppConfiguration,
        store: GameStore
    ) -> ResolvedLaunchSettings {
        let normalized = normalized(bottle, for: store, global: global)
        return GameSettingsResolver.resolve(
            game: game,
            bottle: normalized,
            global: global,
            store: store
        )
    }
}

/// Locates a store exe under both `Program Files` and `Program Files (x86)`.
public enum StoreExecutable {
    public static func candidateRelativePaths(for store: GameStore) -> [String] {
        switch store {
        case .steam:
            return [
                "drive_c/Program Files (x86)/Steam/steam.exe",
                "drive_c/Program Files/Steam/steam.exe"
            ]
        case .epic:
            // Win64 first: DXVK x64 sits next to Portal/Engine Binaries/Win64.
            return [
                "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files (x86)/Epic Games/Launcher/Engine/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files/Epic Games/Launcher/Engine/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files (x86)/Epic Games/EpicGamesLauncher/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files/Epic Games/EpicGamesLauncher/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
                "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
                "drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
                "drive_c/Program Files (x86)/Epic Games/Launcher/Engine/Binaries/Win32/EpicGamesLauncher.exe",
                "drive_c/Program Files/Epic Games/Launcher/Engine/Binaries/Win32/EpicGamesLauncher.exe"
            ]
        case .gog:
            return [
                "drive_c/Program Files (x86)/GOG Galaxy/GalaxyClient.exe",
                "drive_c/Program Files/GOG Galaxy/GalaxyClient.exe"
            ]
        }
    }

    public static func executableName(for store: GameStore) -> String {
        URL(fileURLWithPath: store.executablePath).lastPathComponent
    }

    public static func resolve(
        in prefixURL: URL,
        store: GameStore,
        fileManager: FileManager = .default
    ) -> URL? {
        return launchCandidates(in: prefixURL, store: store, fileManager: fileManager).first
    }

    /// Existing launcher exes in recipe order (Epic: Win32 Portal, Win32 Engine, then Win64).
    public static func launchCandidates(
        in prefixURL: URL,
        store: GameStore,
        fileManager: FileManager = .default
    ) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard fileManager.fileExists(atPath: url.path), seen.insert(key).inserted else { return }
            found.append(url.standardizedFileURL)
        }
        for relative in candidateRelativePaths(for: store) {
            add(prefixURL.appendingPathComponent(relative))
        }
        for extra in searchAll(in: prefixURL, store: store, fileManager: fileManager) {
            add(extra)
        }
        if store == .epic {
            found.sort { epicLaunchScore($0) < epicLaunchScore($1) }
        }
        return found
    }

    public static func isWin32(_ url: URL) -> Bool {
        url.path.contains("Win32")
    }

    public static func isWin64(_ url: URL) -> Bool {
        url.path.contains("Win64")
    }

    public static func searchRoots(in prefixURL: URL, store: GameStore) -> [URL] {
        let drive = prefixURL.appendingPathComponent("drive_c")
        switch store {
        case .steam:
            return [
                drive.appendingPathComponent("Program Files (x86)/Steam"),
                drive.appendingPathComponent("Program Files/Steam")
            ]
        case .epic:
            return [
                drive.appendingPathComponent("Program Files/Epic Games"),
                drive.appendingPathComponent("Program Files (x86)/Epic Games")
            ]
        case .gog:
            return [
                drive.appendingPathComponent("Program Files (x86)/GOG Galaxy"),
                drive.appendingPathComponent("Program Files/GOG Galaxy")
            ]
        }
    }

    private static func searchAll(
        in prefixURL: URL,
        store: GameStore,
        fileManager: FileManager
    ) -> [URL] {
        let name = executableName(for: store)
        var found: [URL] = []
        for root in searchRoots(in: prefixURL, store: store) {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            var visited = 0
            while let item = enumerator?.nextObject() as? URL {
                visited += 1
                if visited > 6_000 { break }
                if item.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                    found.append(item)
                }
            }
        }
        return found
    }

    /// Lower is tried first. Leftover Epic Games Launcher paths, Win64 before Win32.
    static func epicLaunchScore(_ url: URL) -> Int {
        let path = url.path
        if path.contains("Win64"), path.contains("Portal") { return 0 }
        if path.contains("Win64"), path.contains("Engine") { return 1 }
        if path.contains("Win64") { return 2 }
        if path.contains("Win32"), path.contains("Portal") { return 3 }
        if path.contains("Win32") { return 4 }
        return 5
    }
}

/// Download URL, cache name, and Wine argv for each store installer.
public enum StoreInstaller {
    public static let gogFallbackURL =
        "https://content-system.gog.com/open_link/download?path=/open/galaxy/client/setup_galaxy_2.1.10.56.exe"
    public static let gogFallbackFilename = "setup_galaxy_2.1.10.56.exe"
    public static let gogManifestURL =
        "https://remote-config.gog.com/components/webinstaller?component_version=2.0.0"

    public static let gogSilentArguments = [
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-"
    ]

    public static func downloadURL(for store: GameStore) -> String {
        switch store {
        case .steam:
            return "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
        case .epic:
            return ComponentCatalog.legendaryFallback.url.absoluteString
        case .gog:
            return gogFallbackURL
        }
    }

    public static func filename(for store: GameStore) -> String {
        switch store {
        case .steam: return "SteamSetup.exe"
        case .epic: return ComponentCatalog.legendaryFallback.filename
        case .gog: return gogFallbackFilename
        }
    }

    /// Host-path argv passed to `wine`. Steam stays NSIS `/S`.
    public static func wineArguments(installerHostPath: String, store: GameStore) -> [String] {
        switch store {
        case .steam:
            return [installerHostPath, "/S"]
        case .epic:
            return []
        case .gog:
            return [installerHostPath] + gogSilentArguments
        }
    }

    /// `nil` means wait forever (Steam). Epic/GOG must not hang the UI.
    public static func timeout(for store: GameStore) -> TimeInterval? {
        switch store {
        case .steam: return nil
        case .epic, .gog: return 15 * 60
        }
    }

    public static func parseGOGWindowsInstaller(fromJSON json: String) -> (url: URL, filename: String)? {
        let unescaped = json.replacingOccurrences(of: "\\/", with: "/")
        if let data = unescaped.data(using: .utf8),
           let manifest = try? JSONDecoder().decode(GOGWebInstallerManifest.self, from: data),
           let parsed = validatedGOGInstallerURL(manifest.content.windows.downloadLink) {
            return parsed
        }
        guard let start = unescaped.range(
            of: "https://content-system.gog.com/open_link/download?path=/open/galaxy/client/setup_galaxy_"
        ) else { return nil }
        guard let end = unescaped[start.lowerBound...].range(of: ".exe") else { return nil }
        return validatedGOGInstallerURL(String(unescaped[start.lowerBound..<end.upperBound]))
    }

    private static func validatedGOGInstallerURL(_ link: String) -> (url: URL, filename: String)? {
        let cleaned = link.replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"' "))
        guard let url = URL(string: cleaned) else { return nil }
        let filename = gogInstallerFilename(from: url)
        guard filename.lowercased().contains("setup_galaxy"),
              filename.lowercased().hasSuffix(".exe"),
              !filename.lowercased().contains("gog_galaxy_2.0")
        else { return nil }
        return (url, filename)
    }

    /// The CDN puts `setup_galaxy_*.exe` in the `path=` query, not the URL last component.
    static func gogInstallerFilename(from url: URL) -> String {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where item.name == "path" {
                if let value = item.value, let name = value.split(separator: "/").last {
                    return String(name)
                }
            }
        }
        if url.lastPathComponent.lowercased().contains("setup_galaxy") {
            return url.lastPathComponent
        }
        return url.lastPathComponent
    }

    public static func resolvedDownload(for store: GameStore) async -> (url: URL, filename: String) {
        if store == .gog, let latest = await fetchLatestGOGInstaller() {
            return latest
        }
        let fallback = URL(string: downloadURL(for: store))!
        return (fallback, filename(for: store))
    }

    private static func fetchLatestGOGInstaller() async -> (url: URL, filename: String)? {
        guard let manifestURL = URL(string: gogManifestURL) else { return nil }
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return parseGOGWindowsInstaller(fromJSON: json)
    }
}

private struct GOGWebInstallerManifest: Decodable {
    struct Content: Decodable {
        struct Build: Decodable {
            var downloadLink: String
        }
        var windows: Build
    }
    var content: Content
}
