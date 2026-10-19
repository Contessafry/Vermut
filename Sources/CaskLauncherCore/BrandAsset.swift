import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PNG/PDF brand glyphs shipped as copied files (not xcassets), so `swift build`
/// / `./build.sh` always put them in a bundle the app can open.
public enum BrandAsset: String, CaseIterable, Sendable {
    case steam
    case epic
    case gog
    case vermutMark = "vermut-mark"
    case vermutWordmark = "vermut-wordmark"
    case vermutWordmarkWhite = "vermut-wordmark-white"

    /// Tight Bricolage Grotesque "Vermut" bbox at 15pt (see Resources/brand).
    public static let wordmarkAspect: Double = 60.04 / 15.0

    public var isTemplate: Bool {
        switch self {
        case .vermutMark, .vermutWordmark, .vermutWordmarkWhite:
            return false
        default:
            return true
        }
    }

    /// Wordmarks are outlined PDFs; prefer the vector over the PNG fallback.
    public var prefersVector: Bool {
        switch self {
        case .vermutWordmark, .vermutWordmarkWhite:
            return true
        default:
            return false
        }
    }

    public var pngFilenames: [String] {
        ["\(rawValue)@2x.png", "\(rawValue)@3x.png", "\(rawValue).png"]
    }

    public var packagedFilenames: [String] {
        switch self {
        case .vermutMark:
            return ["vermut-mark.png", "vermut-mark@2x.png", "vermut-mark@3x.png"]
        default:
            return ["\(rawValue).png", "\(rawValue)@2x.png", "\(rawValue)@3x.png", "\(rawValue).pdf"]
        }
    }

    /// Preferred PNG bytes (`@2x`, then `@3x`, then `1x`).
    public func pngData() -> Data? {
        url(preferringExtension: "png").flatMap { try? Data(contentsOf: $0) }
    }

    public func pdfData() -> Data? {
        url(preferringExtension: "pdf").flatMap { try? Data(contentsOf: $0) }
    }

    public func url(named file: String) -> URL? {
        for bundle in Self.candidateBundles() {
            if let url = Self.locate(file, in: bundle) {
                return url
            }
        }
        for root in Self.candidateDirectories() {
            let url = root.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public func url(preferringExtension ext: String = "png") -> URL? {
        let files: [String]
        switch ext {
        case "pdf":
            files = ["\(rawValue).pdf"]
        default:
            files = pngFilenames
        }
        for file in files {
            if let url = url(named: file) {
                return url
            }
        }
        return nil
    }

    public static func pngMagicOK(_ data: Data) -> Bool {
        data.count > 8
            && data[data.startIndex] == 0x89
            && data[data.index(data.startIndex, offsetBy: 1)] == 0x50
            && data[data.index(data.startIndex, offsetBy: 2)] == 0x4E
            && data[data.index(data.startIndex, offsetBy: 3)] == 0x47
    }

    private static func locate(_ file: String, in bundle: Bundle) -> URL? {
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        let subdirs = ["BrandAssets", "Contents/Resources/BrandAssets", nil as String?]
        for sub in subdirs {
            if let url = bundle.url(forResource: base, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        if let url = bundle.url(forResource: base, withExtension: ext) {
            return url
        }
        if let root = bundle.resourceURL {
            let direct = root.appendingPathComponent("BrandAssets").appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let nested = root.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        let seen = Box()
        func add(_ bundle: Bundle?) {
            guard let bundle, let url = bundle.resourceURL ?? bundle.bundleURL as URL? else { return }
            if seen.insert(url.path) { bundles.append(bundle) }
        }
        add(Bundle.main)
        #if SWIFT_PACKAGE
        add(Bundle.module)
        #endif
        let names = [
            "CaskLauncherCore_CaskLauncherCore",
            "CaskLauncherApp_CaskLauncherApp",
            "Vermut_CaskLauncherCore",
            "Vermut_CaskLauncherApp"
        ]
        var searchRoots: [URL] = [Bundle.main.bundleURL]
        if let resources = Bundle.main.resourceURL { searchRoots.append(resources) }
        if let exe = Bundle.main.executableURL {
            searchRoots.append(exe.deletingLastPathComponent())
            searchRoots.append(exe.deletingLastPathComponent().appendingPathComponent("../Resources"))
        }
        for root in searchRoots {
            for name in names {
                add(Bundle(url: root.appendingPathComponent("\(name).bundle")))
                add(Bundle(url: root.appendingPathComponent("Contents/Resources/\(name).bundle")))
            }
        }
        return bundles
    }

    private static func candidateDirectories() -> [URL] {
        var dirs: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                dirs.append(standardized)
            }
        }
        if let resources = Bundle.main.resourceURL {
            add(resources.appendingPathComponent("BrandAssets"))
            add(resources)
        }
        add(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BrandAssets"))
        add(Bundle.main.bundleURL.appendingPathComponent("Resources/BrandAssets"))
        if let exe = Bundle.main.executableURL {
            let macOS = exe.deletingLastPathComponent()
            add(macOS.appendingPathComponent("BrandAssets"))
            add(macOS.appendingPathComponent("../Resources/BrandAssets"))
        }
        return dirs
    }
}

private final class Box: @unchecked Sendable {
    private var set: Set<String> = []
    func insert(_ value: String) -> Bool {
        set.insert(value).inserted
    }
}
