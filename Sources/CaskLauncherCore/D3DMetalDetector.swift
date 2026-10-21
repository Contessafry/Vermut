import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Detection / validation state for Apple D3DMetal (never bundled or downloaded).
public enum D3DMetalPresence: Equatable, Sendable {
    case notFound
    case found(version: String?, root: URL)
    case unsupported(version: String?, root: URL)
    case invalid(reason: String)
    case unavailableOnIntel

    public var isUsable: Bool {
        if case .found = self { return true }
        return false
    }

    public var versionString: String? {
        switch self {
        case .found(let version, _), .unsupported(let version, _):
            return version
        default:
            return nil
        }
    }

    public var rootURL: URL? {
        switch self {
        case .found(_, let root), .unsupported(_, let root):
            return root
        default:
            return nil
        }
    }
}

public struct D3DMetalDetectionResult: Equatable, Sendable {
    public var presence: D3DMetalPresence
    public var searchedPaths: [String]

    public init(presence: D3DMetalPresence, searchedPaths: [String] = []) {
        self.presence = presence
        self.searchedPaths = searchedPaths
    }
}

/// Locates and validates Apple Game Porting Toolkit / D3DMetal libraries.
public enum D3DMetalDetector {
    /// Minimum supported D3DMetal short version (GPTK 2.0+).
    public static let minimumVersion = "2.0"

    public static let developerDownloadURL =
        URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!
    public static let developerOverviewURL =
        URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!

    /// Preferred Vermut-managed copy of `redist/lib`.
    public static func vermutLibraryURL(appSupport: URL? = nil) -> URL {
        let root = appSupport ?? PathManager.shared.appSupportURL
        return root.appendingPathComponent("D3DMetal", isDirectory: true)
    }

    /// Common GPTK locations. CrossOver.app is intentionally excluded.
    public static func candidateRoots(
        appSupport: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = [
            vermutLibraryURL(appSupport: appSupport)
        ]

        // Mounted evaluation DMG volumes (temporary but common after install).
        if let volumes = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes", isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for volume in volumes {
                let name = volume.lastPathComponent.lowercased()
                if name.contains("evaluation") && name.contains("windows") {
                    roots.append(volume.appendingPathComponent("redist/lib", isDirectory: true))
                    roots.append(volume.appendingPathComponent("redist/lib/external", isDirectory: true))
                }
            }
        }

        roots.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/lib", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external", isDirectory: true),
            URL(fileURLWithPath: "/opt/local/libexec/d3dmetal", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/lib", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/lib", isDirectory: true),
            home.appendingPathComponent(
                "Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/lib/external",
                isDirectory: true
            )
        ])

        return roots
    }

    public static func detect(
        customPath: String? = nil,
        fileManager: FileManager = .default,
        isAppleSilicon: Bool? = nil
    ) -> D3DMetalDetectionResult {
        if !(isAppleSilicon ?? HostArchitecture.isAppleSilicon) {
            return D3DMetalDetectionResult(presence: .unavailableOnIntel)
        }

        var searched: [String] = []
        var candidates: [URL] = []
        if let customPath, !customPath.isEmpty {
            candidates.append(URL(fileURLWithPath: customPath, isDirectory: true))
        }
        candidates.append(contentsOf: candidateRoots(fileManager: fileManager))

        for root in candidates {
            searched.append(root.path)
            let validation = validate(root: root, fileManager: fileManager)
            switch validation {
            case .found, .unsupported:
                return D3DMetalDetectionResult(presence: validation, searchedPaths: searched)
            case .invalid where customPath != nil && root.path == customPath:
                return D3DMetalDetectionResult(presence: validation, searchedPaths: searched)
            default:
                continue
            }
        }

        if let customPath, !customPath.isEmpty,
           !fileManager.fileExists(atPath: customPath) {
            return D3DMetalDetectionResult(
                presence: .invalid(reason: "The saved location no longer exists (external drive disconnected?)."),
                searchedPaths: searched
            )
        }

        return D3DMetalDetectionResult(presence: .notFound, searchedPaths: searched)
    }

    /// Validates a user-chosen folder (typically `redist/lib` or `redist/lib/external`).
    public static func validate(root: URL, fileManager: FileManager = .default) -> D3DMetalPresence {
        guard fileManager.fileExists(atPath: root.path) else {
            return .invalid(reason: "Could not read the folder. Check permissions.")
        }

        guard let bundleRoot = resolveLibraryRoot(from: root, fileManager: fileManager) else {
            return .invalid(
                reason: "The selected folder does not contain D3DMetal.framework. Select the redist/lib folder."
            )
        }

        let version = readFrameworkVersion(in: bundleRoot, fileManager: fileManager)
        if let version, !ComponentVersion.isAtLeast(version, minimum: minimumVersion) {
            return .unsupported(version: version, root: bundleRoot)
        }
        return .found(version: version, root: bundleRoot)
    }

    /// Finds the directory that contains `external/D3DMetal.framework` or `D3DMetal.framework`.
    public static func resolveLibraryRoot(from root: URL, fileManager: FileManager) -> URL? {
        let candidates = [
            root,
            root.appendingPathComponent("external", isDirectory: true),
            root.appendingPathComponent("lib", isDirectory: true),
            root.appendingPathComponent("lib/external", isDirectory: true),
            root.appendingPathComponent("redist/lib", isDirectory: true),
            root.appendingPathComponent("redist/lib/external", isDirectory: true)
        ]
        for candidate in candidates {
            if frameworkURL(in: candidate, fileManager: fileManager) != nil {
                // Prefer the parent that also has wine/x86_64-windows when present.
                let parent = candidate.lastPathComponent == "external"
                    ? candidate.deletingLastPathComponent()
                    : candidate
                return parent
            }
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("libd3dshared.dylib").path) {
                return candidate
            }
        }
        return nil
    }

    public static func frameworkURL(in root: URL, fileManager: FileManager) -> URL? {
        let direct = root.appendingPathComponent("D3DMetal.framework", isDirectory: true)
        if fileManager.fileExists(atPath: direct.path) { return direct }
        let nested = root.appendingPathComponent("external/D3DMetal.framework", isDirectory: true)
        if fileManager.fileExists(atPath: nested.path) { return nested }
        return nil
    }

    public static func readFrameworkVersion(in root: URL, fileManager: FileManager) -> String? {
        guard let framework = frameworkURL(in: root, fileManager: fileManager) else { return nil }
        let plistURL = framework.appendingPathComponent("Versions/Current/Resources/Info.plist")
        let alt = framework.appendingPathComponent("Resources/Info.plist")
        for url in [plistURL, alt] {
            guard let data = fileManager.contents(atPath: url.path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            if let short = plist["CFBundleShortVersionString"] as? String, !short.isEmpty {
                return short
            }
            if let version = plist["CFBundleVersion"] as? String, !version.isEmpty {
                return version
            }
        }
        return nil
    }

    public static let installGuideSteps: [(title: String, detail: String)] = [
        (
            "Sign in to developer.apple.com with an Apple Account (free).",
            "Open the Apple Developer site and sign in."
        ),
        (
            "Download “Game Porting Toolkit” (.dmg) from the Downloads page.",
            "Search for Game Porting Toolkit on the developer downloads list."
        ),
        (
            "Open the .dmg, then open “Evaluation environment for Windows games” and accept the licence.",
            "This mounts the evaluation environment volume."
        ),
        (
            "Copy the redist/lib folder to a stable location and choose “Point to location…”.",
            "Suggested: Application Support/Vermut/D3DMetal."
        )
    ]
}

public enum HostArchitecture {
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #elseif canImport(Darwin)
        // Rosetta process on Apple Silicon still reports x86_64; prefer sysctl when available.
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        if result == 0 { return value == 1 }
        return false
        #else
        return false
        #endif
    }
}
