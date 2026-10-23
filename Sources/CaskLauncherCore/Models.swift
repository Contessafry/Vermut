import Foundation

/// Public project identity. Product name is Vermut; Swift targets stay CaskLauncher*.
public enum VermutProject {
    public static let name = "Vermut"
    public static let version = "1.2.0"
    /// Library empty state. GOG is "Coming soon", so it is not offered here.
    public static let libraryEmptyMessage = "Install Steam or Epic from Stores to see your games here."
    public static let tagline = "Pour. Click. Play."
    public static let githubOwner = "Contessafry"
    public static let githubRepository = "Vermut"
    public static let githubURL = URL(string: "https://github.com/Contessafry/Vermut")!
    public static let licenseURL = URL(string: "https://github.com/Contessafry/Vermut/blob/main/LICENSE")!

    public static var githubDisplay: String {
        "github.com/\(githubOwner)/\(githubRepository)"
    }
}

public enum GameStore: String, CaseIterable, Identifiable, Sendable {
    case steam = "Steam"
    case epic = "Epic Games Store"
    case gog = "GOG Galaxy"

    public var id: String { rawValue }

    public var identifier: String {
        switch self {
        case .steam: return "steam"
        case .epic: return "epic"
        case .gog: return "gog"
        }
    }

    /// Copied PNG/PDF glyph in `BrandAssets/` (not the asset catalog).
    public var brandAsset: BrandAsset {
        switch self {
        case .steam: return .steam
        case .epic: return .epic
        case .gog: return .gog
        }
    }

    public var installerURL: String {
        switch self {
        case .epic:
            return LegendaryCLI.sourceURL.absoluteString
        default:
            return StoreInstaller.downloadURL(for: self)
        }
    }

    public var installerFilename: String {
        StoreInstaller.filename(for: self)
    }

    public var executablePath: String {
        switch self {
        case .steam:
            return "drive_c/Program Files (x86)/Steam/steam.exe"
        case .epic:
            return "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        case .gog:
            return "drive_c/Program Files (x86)/GOG Galaxy/GalaxyClient.exe"
        }
    }

    public var launchEnvironment: [String: String] {
        switch self {
        case .steam, .epic, .gog:
            return [:]
        }
    }
}

public enum InstallerPhase: String, Sendable, Equatable {
    case settingUp
    case awaitingWindow
    /// Store installed; its client is downloading its first self-update.
    case updatingClient
}

public enum StoreStatus: Sendable, Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installing(InstallerPhase)
    case installed
    case running
    case error(String)

    public var isInstallInProgress: Bool {
        switch self {
        case .downloading, .installing: return true
        default: return false
        }
    }

    /// Status the periodic refresh should show. An install in progress is never
    /// overridden by "installed": store installers (e.g. SteamSetup) write the
    /// launcher exe long before setup finishes. Errors stick until retried.
    public static func refreshed(
        current: StoreStatus?,
        isRunning: Bool,
        isInstalled: Bool
    ) -> StoreStatus {
        // Steam's first-run update runs the client itself: "running" must not
        // short-circuit the setup stages (it skipped "Finishing" in 1.1.3 testing).
        if case .installing(.updatingClient)? = current { return .installing(.updatingClient) }
        if isRunning { return .running }
        if let current, current.isInstallInProgress { return current }
        if case .error = current { return current! }
        return isInstalled ? .installed : .notInstalled
    }
}

public enum GraphicsBackend: String, CaseIterable, Identifiable, Sendable {
    case dxmt = "DXMT (DX10/11 on Metal)"
    case dxvk = "DXVK + MoltenVK (DX to Vulkan to Metal)"
    case d3dmetal = "D3DMetal (Apple GPTK - DX12)"
    case wined3d = "WineD3D (OpenGL fallback)"

    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .d3dmetal: return "D3DMetal"
        case .wined3d: return "WineD3D"
        }
    }
}

public enum WineEngine: String, CaseIterable, Identifiable, Sendable {
    case grappleWine = "grapple-wine"
    case staging
    case devel

    public static let defaultEngine: WineEngine = .grappleWine

    public var id: String { rawValue }

    /// Maps a stored engine id to a current case. Unknown or legacy names
    /// (e.g. `"Wine 11 (CrossOver)"`) become the default engine.
    public static func resolved(from stored: String) -> WineEngine {
        WineEngine(rawValue: stored) ?? .defaultEngine
    }

    public var displayName: String {
        userFacingName
    }

    /// Shown in the UI. Internal id remains `grapple-wine`.
    public var userFacingName: String {
        switch self {
        case .grappleWine: return "Vermut Wine"
        case .staging: return "Wine Staging 11.18"
        case .devel: return "Wine Devel 11.18"
        }
    }

    /// Second line in engine pickers / Settings › Wine Engines.
    public var subtitle: String {
        switch self {
        case .grappleWine: return "Recommended · included"
        case .staging: return "Gcenx · WineHQ · experimental patches"
        case .devel: return "Gcenx · WineHQ · development"
        }
    }

    /// DXMT needs winemac Metal views; only the CrossOver-based grapple-wine build exports them.
    public var supportsDXMT: Bool {
        self == .grappleWine
    }

    /// Gcenx staging/devel builds expect a system GStreamer.framework.
    public var requiresGStreamer: Bool {
        self == .staging || self == .devel
    }

    var githubAssetPrefix: String {
        switch self {
        case .grappleWine: return "grapple-wine-"
        case .staging: return "wine-staging-"
        case .devel: return "wine-devel-"
        }
    }
}

public struct BottleConfiguration: Codable, Sendable, Equatable {
    /// `SettingInheritance.automatic` or a `WineEngine.rawValue`.
    public var engine: String
    public var graphicsBackend: String
    /// `SettingInheritance.automatic` or a DXMT tag such as `v0.80`.
    public var dxmtVersion: String
    /// `SettingInheritance.automatic` or a `WineLogLevel.rawValue`.
    public var logLevel: String
    public var enableHiDPI: Bool
    public var windowsVersion: String

    public init(
        engine: String = SettingInheritance.automatic,
        graphicsBackend: String = GraphicsBackend.dxmt.rawValue,
        dxmtVersion: String = SettingInheritance.automatic,
        logLevel: String = SettingInheritance.automatic,
        enableHiDPI: Bool = true,
        windowsVersion: String = "win10"
    ) {
        self.engine = engine
        self.graphicsBackend = graphicsBackend
        self.dxmtVersion = dxmtVersion
        self.logLevel = logLevel
        self.enableHiDPI = enableHiDPI
        self.windowsVersion = windowsVersion
    }

    enum CodingKeys: String, CodingKey {
        case engine, graphicsBackend, dxmtVersion, logLevel, enableHiDPI, windowsVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decodeIfPresent(String.self, forKey: .engine) ?? SettingInheritance.automatic
        graphicsBackend = try container.decodeIfPresent(String.self, forKey: .graphicsBackend)
            ?? GraphicsBackend.dxmt.rawValue
        dxmtVersion = try container.decodeIfPresent(String.self, forKey: .dxmtVersion)
            ?? SettingInheritance.automatic
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel)
            ?? SettingInheritance.automatic
        enableHiDPI = try container.decodeIfPresent(Bool.self, forKey: .enableHiDPI) ?? true
        windowsVersion = try container.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win10"
    }
}

public struct AppConfiguration: Codable, Sendable {
    public var defaultEngine: String
    public var defaultGraphicsBackend: String
    /// Global default DXMT tag (first launch: pinned catalog default, currently v0.80).
    public var defaultDXMTVersion: String
    /// Global default log level (`WineLogLevel.rawValue`). Automatic tiers fall back to store soft-defaults.
    public var defaultLogLevel: String
    /// User-selected `redist/lib` (or parent) path for Apple D3DMetal. Never bundled.
    public var d3dMetalLibraryPath: String?
    /// In-app update feed: Stable (default) or Beta (GitHub pre-releases).
    public var updateChannel: String
    public var enableHiDPI: Bool
    public var windowsVersion: String

    public var resolvedUpdateChannel: UpdateChannel {
        UpdateChannel.resolved(from: updateChannel)
    }

    public init(
        defaultEngine: String = WineEngine.defaultEngine.rawValue,
        defaultGraphicsBackend: String = GraphicsBackend.dxmt.rawValue,
        defaultDXMTVersion: String = "v0.80",
        defaultLogLevel: String = WineLogLevel.off.rawValue,
        d3dMetalLibraryPath: String? = nil,
        updateChannel: String = UpdateChannel.stable.rawValue,
        enableHiDPI: Bool = true,
        windowsVersion: String = "win10"
    ) {
        self.defaultEngine = defaultEngine
        self.defaultGraphicsBackend = defaultGraphicsBackend
        self.defaultDXMTVersion = defaultDXMTVersion
        self.defaultLogLevel = defaultLogLevel
        self.d3dMetalLibraryPath = d3dMetalLibraryPath
        self.updateChannel = updateChannel
        self.enableHiDPI = enableHiDPI
        self.windowsVersion = windowsVersion
    }

    enum CodingKeys: String, CodingKey {
        case defaultEngine, defaultGraphicsBackend, defaultDXMTVersion, defaultLogLevel
        case d3dMetalLibraryPath, updateChannel, enableHiDPI, windowsVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultEngine = try container.decodeIfPresent(String.self, forKey: .defaultEngine)
            ?? WineEngine.defaultEngine.rawValue
        defaultGraphicsBackend = try container.decodeIfPresent(String.self, forKey: .defaultGraphicsBackend)
            ?? GraphicsBackend.dxmt.rawValue
        defaultDXMTVersion = try container.decodeIfPresent(String.self, forKey: .defaultDXMTVersion)
            ?? "v0.80"
        defaultLogLevel = try container.decodeIfPresent(String.self, forKey: .defaultLogLevel)
            ?? WineLogLevel.off.rawValue
        d3dMetalLibraryPath = try container.decodeIfPresent(String.self, forKey: .d3dMetalLibraryPath)
        updateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
            ?? UpdateChannel.stable.rawValue
        enableHiDPI = try container.decodeIfPresent(Bool.self, forKey: .enableHiDPI) ?? true
        windowsVersion = try container.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win10"
    }

    /// Returns true when `defaultEngine` was rewritten from an unknown/legacy value.
    public mutating func migrateLegacyEngineIfNeeded() -> Bool {
        let resolved = WineEngine.resolved(from: defaultEngine)
        guard resolved.rawValue != defaultEngine else { return false }
        defaultEngine = resolved.rawValue
        return true
    }
}

public struct ResolvedComponent: Equatable, Sendable {
    public var name: String
    public var version: String
    public var url: URL
    public var filename: String
    public var sha256: String?

    public init(name: String, version: String, url: URL, filename: String, sha256: String?) {
        self.name = name
        self.version = version
        self.url = url
        self.filename = filename
        self.sha256 = sha256
    }
}

public struct ComponentManifest: Codable, Sendable {
    public var components: [Component]

    public struct Component: Codable, Sendable {
        public var name: String
        public var version: String
        public var url: String
        public var sha256: String?
        public var filename: String
    }
}
