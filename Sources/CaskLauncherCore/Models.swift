import Foundation

/// Public project identity. Product name is Vermut; Swift targets stay CaskLauncher*.
public enum VermutProject {
    public static let name = "Vermut"
    public static let version = "1.1.0"
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
        case .grappleWine: return "Vermut Wine 11 (DXMT build)"
        case .staging: return "Wine Staging 11"
        case .devel: return "Wine Devel 11"
        }
    }

    /// DXMT needs winemac Metal views; only the CrossOver-based grapple-wine build exports them.
    public var supportsDXMT: Bool {
        self == .grappleWine
    }

    var githubAssetPrefix: String {
        switch self {
        case .grappleWine: return "grapple-wine-"
        case .staging: return "wine-staging-"
        case .devel: return "wine-devel-"
        }
    }
}

public struct BottleConfiguration: Codable, Sendable {
    public var engine: String
    public var graphicsBackend: String
    public var enableHiDPI: Bool
    public var windowsVersion: String

    public init(
        engine: String = WineEngine.defaultEngine.rawValue,
        graphicsBackend: String = GraphicsBackend.dxmt.rawValue,
        enableHiDPI: Bool = true,
        windowsVersion: String = "win10"
    ) {
        self.engine = engine
        self.graphicsBackend = graphicsBackend
        self.enableHiDPI = enableHiDPI
        self.windowsVersion = windowsVersion
    }
}

public struct AppConfiguration: Codable, Sendable {
    public var defaultEngine: String
    public var defaultGraphicsBackend: String
    public var enableHiDPI: Bool
    public var windowsVersion: String

    public init(
        defaultEngine: String = WineEngine.defaultEngine.rawValue,
        defaultGraphicsBackend: String = GraphicsBackend.dxmt.rawValue,
        enableHiDPI: Bool = true,
        windowsVersion: String = "win10"
    ) {
        self.defaultEngine = defaultEngine
        self.defaultGraphicsBackend = defaultGraphicsBackend
        self.enableHiDPI = enableHiDPI
        self.windowsVersion = windowsVersion
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
