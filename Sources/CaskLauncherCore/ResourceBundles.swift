import Foundation

/// Locates SwiftPM resource bundles without using the generated `Bundle.module`
/// accessor, which calls `fatalError` when the bundle is not at the .app root or
/// at the absolute `.build` path of the machine that built it.
public enum VermutResources {
    private final class Marker {}

    /// Names SwiftPM gives the resource bundles (`<Package>_<Target>.bundle`).
    public static let coreBundleNames = ["Vermut_CaskLauncherCore", "CaskLauncherCore_CaskLauncherCore"]
    public static let appBundleNames = ["Vermut_CaskLauncherApp", "CaskLauncherApp_CaskLauncherApp"]

    /// Existing bundles matching `names`, searched in Bundle.main.resourceURL,
    /// Bundle.main.bundleURL, the executable's folder and next to the framework/binary
    /// that contains this code. Never traps; returns an empty array if nothing is found.
    public static func bundles(named names: [String]) -> [Bundle] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL { roots.append(exe.deletingLastPathComponent()) }
        let own = Bundle(for: Marker.self)
        if let resources = own.resourceURL { roots.append(resources) }
        roots.append(own.bundleURL)
        roots.append(own.bundleURL.deletingLastPathComponent())

        var found: [Bundle] = []
        var seen = Set<String>()
        for root in roots {
            for name in names {
                let url = root.appendingPathComponent("\(name).bundle").standardizedFileURL
                guard seen.insert(url.path).inserted,
                      FileManager.default.fileExists(atPath: url.path),
                      let bundle = Bundle(url: url) else { continue }
                found.append(bundle)
            }
        }
        return found
    }

    public static var coreBundles: [Bundle] { bundles(named: coreBundleNames) }
    public static var appBundles: [Bundle] { bundles(named: appBundleNames) }
}
