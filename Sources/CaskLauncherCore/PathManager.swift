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
    
    public func prefixURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("prefix")
    }
    
    public func bottleLogsURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("logs")
    }
    
    public func bottleConfigURL(for store: GameStore) -> URL {
        bottleURL(for: store).appendingPathComponent("bottle.json")
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
    
    public func dxmtURL() -> URL {
        enginesURL.appendingPathComponent("dxmt")
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

    public func dxmtOverlay() -> OverlayLayout? {
        OverlayLayout.resolve(installRoot: dxmtURL(), fileManager: fileManager)
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
