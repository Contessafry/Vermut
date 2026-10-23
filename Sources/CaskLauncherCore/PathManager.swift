import Foundation

public final class PathManager: @unchecked Sendable {
    public static let shared = PathManager()
    
    private let fileManager = FileManager.default
    
    public let appSupportURL: URL
    public let enginesURL: URL
    public let bottlesURL: URL
    public let cacheURL: URL
    public let configURL: URL
    public let componentsManifestURL: URL
    public let migrationDeferred: Bool
    public let migratedFromLegacy: Bool
    public let usedLegacyFallback: Bool
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let outcome = DataDirectoryMigration.resolve(applicationSupport: appSupport)
        appSupportURL = outcome.appSupportURL
        migrationDeferred = outcome.deferred
        migratedFromLegacy = outcome.migrated
        usedLegacyFallback = outcome.usedFallback
        
        enginesURL = appSupportURL.appendingPathComponent("engines")
        bottlesURL = appSupportURL.appendingPathComponent("bottles")
        cacheURL = appSupportURL.appendingPathComponent("cache")
        configURL = appSupportURL.appendingPathComponent("config.json")
        componentsManifestURL = cacheURL.appendingPathComponent("components.json")
    }
    
    public func bottleURL(for store: GameStore) -> URL {
        bottlesURL.appendingPathComponent(store.identifier)
    }

    /// Custom bottle folder named by UUID (never the user-facing name).
    public func customBottleURL(id: UUID) -> URL {
        bottlesURL.appendingPathComponent(id.uuidString)
    }

    public func prefixURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("prefix")
    }

    public func customPrefixURL(id: UUID) -> URL {
        customBottleURL(id: id).appendingPathComponent("prefix")
    }
    
    public func bottleLogsURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("logs")
    }

    public func customBottleLogsURL(id: UUID) -> URL {
        customBottleURL(id: id).appendingPathComponent("logs")
    }
    
    public func bottleConfigURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("bottle.json")
    }

    public func customBottleConfigURL(id: UUID) -> URL {
        customBottleURL(id: id).appendingPathComponent("bottle.json")
    }

    public func customLogURL(id: UUID) -> URL {
        customBottleLogsURL(id: id).appendingPathComponent("bottle.log")
    }

    /// Per-game overrides: `bottles/<store>/games/<appId>.json`.
    public func gamesDirectoryURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("games", isDirectory: true)
    }

    public func gameConfigURL(for store: GameStore, appId: String) -> URL {
        let safe = Self.sanitizedGameFileName(appId)
        return gamesDirectoryURL(for: store).appendingPathComponent("\(safe).json")
    }

    /// Keeps app ids filesystem-safe while remaining stable for round-trips.
    public static func sanitizedGameFileName(_ appId: String) -> String {
        let trimmed = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
    }
    
    public func logURL(for store: GameStore) -> URL {
        bottleLogsURL(for: store).appendingPathComponent("\(store.identifier).log")
    }
    
    public func installerURL(for store: GameStore) -> URL {
        cacheURL.appendingPathComponent(store.installerFilename)
    }
    
    public func engineURL(for engine: WineEngine) -> URL {
        enginesURL.appendingPathComponent(engine.id)
    }
    
    /// Classic DXMT store root (`engines/dxmt`). Same path as 1.1.3 / main.
    /// Side-by-side builds live in `engines/dxmt/versions/<tag>/`.
    public func dxmtURL() -> URL {
        enginesURL.appendingPathComponent("dxmt", isDirectory: true)
    }

    /// Parent folder for DXMT version installs and the active-version pointer.
    public func dxmtStoreURL() -> URL {
        dxmtURL()
    }
    
    public func dxvkURL() -> URL {
        enginesURL.appendingPathComponent("dxvk")
    }

    /// Native Legendary binary. Not executed under Wine.
    public var legendaryBinaryURL: URL {
        enginesURL.appendingPathComponent("legendary").appendingPathComponent("legendary")
    }

    /// `LEGENDARY_CONFIG_PATH` — lives in the Epic bottle folder.
    public var legendaryConfigURL: URL {
        bottleURL(for: .epic).appendingPathComponent("legendary")
    }
    
    public func ensureDirectoriesExist() throws {
        // Uninstall wipe: do not recreate empty bottles/engines/cache/covers after trash.
        if UninstallPersistenceGate.writesSuppressed { return }
        let directories = [
            appSupportURL,
            enginesURL,
            bottlesURL,
            cacheURL,
            cacheURL.appendingPathComponent("covers", isDirectory: true)
        ]
        
        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func engineLayout(for engine: WineEngine) -> EngineLayout? {
        EngineLayout.resolve(installRoot: engineURL(for: engine), fileManager: fileManager)
    }
    
    public func wineExecutable(engine: WineEngine) -> URL? {
        engineLayout(for: engine)?.wineExecutable
    }
    
    public func wineserverExecutable(engine: WineEngine) -> URL? {
        engineLayout(for: engine)?.wineserverExecutable
    }

    /// DXMT overlay for Automatic launches — same order as main 1.1.3 when a flat
    /// `engines/dxmt` tree exists; falls back to the active side-by-side install only
    /// after migration emptied the classic root.
    public func dxmtOverlay() -> OverlayLayout? {
        if let flat = OverlayLayout.resolve(installRoot: dxmtURL(), fileManager: fileManager),
           flat.hasD3D11 {
            return flat
        }
        if let active = OverlayLayout.resolve(
            installRoot: DXMTVersionManager.shared.activeOverlayURL(),
            fileManager: fileManager
        ), active.hasD3D11 {
            return active
        }
        return nil
    }

    public func dxvkOverlay() -> OverlayLayout? {
        OverlayLayout.resolve(installRoot: dxvkURL(), fileManager: fileManager)
    }
    
    public func isDXMTInstalled() -> Bool {
        dxmtOverlay()?.hasD3D11 == true
    }
    
    public func dxmtLibraryPath() -> URL? {
        dxmtOverlay()?.root
    }
    
    public func dxvkLibraryPath() -> URL? {
        dxvkOverlay()?.root
    }
}
