import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resolves download URLs from the GitHub Releases API, with pinned fallbacks
/// that were verified by HTTP HEAD/range on 2026-10-06.
public enum ComponentCatalog {
    public static let wineRepo = "Gcenx/macOS_Wine_builds"
    public static let grappleWineRepo = "MartijnBud/grapple-releases"
    public static let dxmtRepo = "3Shain/dxmt"
    public static let dxvkRepo = "Gcenx/DXVK-macOS"
    /// Historical URL `github.com/derrod/legendary` redirects here.
    public static let legendaryRepo = "legendary-gl/legendary"

    public static let wineStagingFallback = ResolvedComponent(
        name: "wine-staging",
        version: "11.18",
        url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz")!,
        filename: "wine-staging-11.18-osx64.tar.xz",
        sha256: "b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127"
    )

    public static let wineDevelFallback = ResolvedComponent(
        name: "wine-devel",
        version: "11.18",
        url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz")!,
        filename: "wine-devel-11.18-osx64.tar.xz",
        sha256: "aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82"
    )

    /// Pinned fallback: release v0.2.5-beta.1 / asset grapple-wine-1.0.2.tar.xz.
    /// SHA-256 computed on this VM from the downloaded archive.
    public static let grappleWineFallback = ResolvedComponent(
        name: "grapple-wine",
        version: "1.0.2",
        url: URL(string: "https://github.com/MartijnBud/grapple-releases/releases/download/v0.2.5-beta.1/grapple-wine-1.0.2.tar.xz")!,
        filename: "grapple-wine-1.0.2.tar.xz",
        sha256: "db4925788bef2f83404bb685e2304cb923d62c5759312ee639822aaf85b34a5c"
    )

    public static let dxmtFallback = ResolvedComponent(
        name: "dxmt",
        version: "v0.80",
        url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
        filename: "dxmt-v0.80-builtin.tar.gz",
        sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
    )

    /// Builtin Wine overlay: d3d11/d3d10core only. GitHub "latest" is this pack.
    public static let dxvkBuiltinFallback = ResolvedComponent(
        name: "dxvk-builtin",
        version: "v1.10.3-20230507-repack",
        url: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack-builtin.tar.gz")!,
        filename: "dxvk-macOS-async-v1.10.3-20230507-repack-builtin.tar.gz",
        sha256: "810b1e5caf8ce975b784fae866a130ad23fa0ea233b0e5609cbc4a45f3ef6f00"
    )

    /// Official macOS arm64 binary from Legendary 0.21.1. SHA-256 from the GitHub release digest.
    public static let legendaryFallback = ResolvedComponent(
        name: "legendary",
        version: "0.21.1",
        url: URL(string: "https://github.com/legendary-gl/legendary/releases/download/0.21.1/legendary_macOS_arm64")!,
        filename: "legendary_macOS_arm64",
        sha256: "d87978321dba9cb731fab40c72f0a30bed55baca8b5341ab21024c5733cd837e"
    )

    /// pal1000 mesa-dist-win MSVC pack. Qt `QT_OPENGL=software` loads `opengl32sw.dll`;
    /// this archive ships the Mesa WGL loader as `x64/opengl32.dll` plus `libgallium_wgl.dll`.
    public static let mesaDistWinFallback = ResolvedComponent(
        name: "mesa-dist-win",
        version: "26.2.5",
        url: URL(string: "https://github.com/pal1000/mesa-dist-win/releases/download/26.2.5/mesa3d-26.2.5-release-msvc.7z")!,
        filename: "mesa3d-26.2.5-release-msvc.7z",
        sha256: "997123ef4ce8896204ab912d5b54f19372c487ff9835bcefafa2fca23b8953c2"
    )

    /// Official 7-Zip extra `7zz` (macOS). Used only to unpack the Mesa `.7z`.
    public static let sevenZipMacFallback = ResolvedComponent(
        name: "7zz",
        version: "25.01",
        url: URL(string: "https://www.7-zip.org/a/7z2501-mac.tar.xz")!,
        filename: "7z2501-mac.tar.xz",
        sha256: "26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0"
    )

    /// Official 7-Zip extra `7zz` (Linux x64). Host-tool fallback for `swift test`.
    public static let sevenZipLinuxFallback = ResolvedComponent(
        name: "7zz",
        version: "25.01",
        url: URL(string: "https://www.7-zip.org/a/7z2501-linux-x64.tar.xz")!,
        filename: "7z2501-linux-x64.tar.xz",
        sha256: "4ca3b7c6f2f67866b92622818b58233dc70367be2f36b498eb0bdeaaa44b53f4"
    )

    /// Full x64 pack with d3d9/d3d10core/d3d11/dxgi. The -repack tarball omits dxgi.
    public static let dxvkFallback = ResolvedComponent(
        name: "dxvk",
        version: "v1.10.3-20230507",
        url: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz")!,
        filename: "dxvk-macOS-async-v1.10.3-20230507.tar.gz",
        sha256: "f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516"
    )

    public static func fallback(for engine: WineEngine) -> ResolvedComponent {
        switch engine {
        case .grappleWine: return grappleWineFallback
        case .staging: return wineStagingFallback
        case .devel: return wineDevelFallback
        }
    }

    public static func isGrappleWineArchive(_ filename: String) -> Bool {
        let name = filename.lowercased()
        return name.hasPrefix("grapple-wine-")
            && name.hasSuffix(".tar.xz")
            && !name.contains("source")
    }

    public static func resolveWine(_ engine: WineEngine) async -> ResolvedComponent {
        switch engine {
        case .grappleWine:
            return await resolveGrappleWine()
        case .staging, .devel:
            return await resolveGcenxWine(engine)
        }
    }

    public static func resolveGrappleWine() async -> ResolvedComponent {
        let fallback = grappleWineFallback
        var releases: [GitHubRelease] = []
        if let latest = try? await latestRelease(repo: grappleWineRepo) {
            releases.append(latest)
        }
        if releases.first?.assets.contains(where: { isGrappleWineArchive($0.name) }) != true {
            if let listed = try? await listReleases(repo: grappleWineRepo, perPage: 10) {
                releases.append(contentsOf: listed)
            }
        }
        for release in releases {
            if let asset = release.assets.first(where: { isGrappleWineArchive($0.name) }),
               let url = URL(string: asset.browserDownloadUrl) {
                let sha = parseDigest(asset.digest)
                    ?? (asset.name == fallback.filename ? fallback.sha256 : nil)
                    ?? fallback.sha256
                return ResolvedComponent(
                    name: fallback.name,
                    version: release.tagName,
                    url: url,
                    filename: asset.name,
                    sha256: sha
                )
            }
        }
        return fallback
    }

    public static func isGcenxWineArchive(_ filename: String, engine: WineEngine) -> Bool {
        let name = filename.lowercased()
        return name.hasPrefix(engine.githubAssetPrefix.lowercased())
            && name.hasSuffix("-osx64.tar.xz")
    }

    /// Newest matching Gcenx `osx64` tarball first. Versions are never hardcoded.
    public static func listGcenxWineReleases(
        engine: WineEngine,
        perPage: Int = 15
    ) async -> [ResolvedComponent] {
        let fallback = fallback(for: engine)
        var releases: [GitHubRelease] = []
        if let listed = try? await listReleases(repo: wineRepo, perPage: perPage) {
            releases = listed
        } else if let latest = try? await latestRelease(repo: wineRepo) {
            releases = [latest]
        }
        var results: [ResolvedComponent] = []
        var seen = Set<String>()
        for release in releases {
            guard isOfferedStableRelease(
                tagName: release.tagName,
                prerelease: release.prerelease ?? false,
                draft: release.draft ?? false,
                assetNames: release.assets.map(\.name)
            ) else { continue }
            guard let asset = release.assets.first(where: { isGcenxWineArchive($0.name, engine: engine) }),
                  let url = URL(string: asset.browserDownloadUrl) else { continue }
            let tag = release.tagName
            guard seen.insert(tag).inserted else { continue }
            results.append(
                ResolvedComponent(
                    name: fallback.name,
                    version: tag,
                    url: url,
                    filename: asset.name,
                    sha256: parseDigest(asset.digest)
                        ?? (asset.name == fallback.filename ? fallback.sha256 : nil)
                )
            )
        }
        return results.sorted {
            ComponentVersion.compare($0.version, $1.version) == .orderedDescending
        }
    }

    static func resolveGcenxWine(_ engine: WineEngine) async -> ResolvedComponent {
        let listed = await listGcenxWineReleases(engine: engine)
        return listed.first ?? fallback(for: engine)
    }

    /// Nightly / pre-release / draft GitHub assets are never offered for DXMT or Gcenx Wine.
    public static func isOfferedStableRelease(
        tagName: String,
        prerelease: Bool,
        draft: Bool,
        assetNames: [String]
    ) -> Bool {
        if prerelease || draft { return false }
        let tag = tagName.lowercased()
        if tag.contains("nightly") { return false }
        if assetNames.contains(where: { $0.lowercased().contains("nightly") }) { return false }
        return true
    }

    /// Prefers the pinned default (`v0.80`) so first installs stay on the LGPL baseline.
    /// Pass `tag` to resolve a specific release; falls back to the pinned asset when offline.
    public static func resolveDXMT(tag: String? = nil) async -> ResolvedComponent {
        let preferred = tag.map(ComponentVersion.canonicalTag) ?? DXMTVersionManager.defaultVersionTag
        let releases = await listDXMTReleases()
        if let match = releases.first(where: {
            ComponentVersion.canonicalTag($0.version) == preferred
        }) {
            return match
        }
        if tag == nil, let latest = releases.first {
            // Only use "latest" when the preferred default is missing from the API
            // and the caller did not ask for a specific tag.
            if ComponentVersion.canonicalTag(latest.version) == preferred {
                return latest
            }
        }
        if preferred == ComponentVersion.canonicalTag(dxmtFallback.version) {
            return dxmtFallback
        }
        // Specific unknown tag: still return fallback metadata shaped for that tag
        // only when it matches the pinned default; otherwise prefer fallback.
        return dxmtFallback
    }

    public static func isDXMTBuiltinArchive(_ filename: String) -> Bool {
        let name = filename.lowercased()
        return name.hasSuffix(".tar.gz")
            && name.contains("dxmt")
            && name.contains("builtin")
            && !name.contains("source")
    }

    public static func isDXMTArchive(_ filename: String) -> Bool {
        let name = filename.lowercased()
        return name.hasSuffix(".tar.gz")
            && name.contains("dxmt")
            && !name.contains("source")
    }

    /// Lists DXMT GitHub releases that ship a usable overlay tarball (newest first).
    public static func listDXMTReleases(perPage: Int = 20) async -> [ResolvedComponent] {
        var results: [ResolvedComponent] = []
        let releases: [GitHubRelease]
        if let listed = try? await listReleases(repo: dxmtRepo, perPage: perPage) {
            releases = listed
        } else if let latest = try? await latestRelease(repo: dxmtRepo) {
            releases = [latest]
        } else {
            return [dxmtFallback]
        }

        for release in releases {
            guard isOfferedStableRelease(
                tagName: release.tagName,
                prerelease: release.prerelease ?? false,
                draft: release.draft ?? false,
                assetNames: release.assets.map(\.name)
            ) else { continue }
            let asset = release.assets.first(where: { isDXMTBuiltinArchive($0.name) })
                ?? release.assets.first(where: { isDXMTArchive($0.name) })
            guard let asset, let url = URL(string: asset.browserDownloadUrl) else { continue }
            let tag = ComponentVersion.canonicalTag(release.tagName)
            let sha = parseDigest(asset.digest)
                ?? (asset.name == dxmtFallback.filename ? dxmtFallback.sha256 : nil)
            results.append(
                ResolvedComponent(
                    name: "dxmt",
                    version: tag,
                    url: url,
                    filename: asset.name,
                    sha256: sha ?? (tag == dxmtFallback.version ? dxmtFallback.sha256 : nil)
                )
            )
        }

        if results.isEmpty {
            return [dxmtFallback]
        }
        // Ensure the pinned default is present for offline-friendly install UI.
        let defaultTag = ComponentVersion.canonicalTag(dxmtFallback.version)
        if !results.contains(where: { ComponentVersion.canonicalTag($0.version) == defaultTag }) {
            results.append(dxmtFallback)
        }
        return results.sorted {
            ComponentVersion.compare($0.version, $1.version) == .orderedDescending
        }
    }

    /// True for the macOS tarball that ships `x64/dxgi.dll` (not builtin, not the dxgi-less repack).
    public static func isDXVKArchiveWithDxgi(_ filename: String) -> Bool {
        let name = filename.lowercased()
        return name.hasSuffix(".tar.gz")
            && name.contains("macos")
            && !name.contains("builtin")
            && !name.contains("repack")
            && !name.contains("crossover")
    }

    public static func resolveDXVK() async -> ResolvedComponent {
        var releases: [GitHubRelease] = []
        if let listed = try? await listReleases(repo: dxvkRepo, perPage: 15) {
            releases.append(contentsOf: listed)
        } else if let latest = try? await latestRelease(repo: dxvkRepo) {
            releases.append(latest)
        }
        for release in releases {
            if let asset = release.assets.first(where: { isDXVKArchiveWithDxgi($0.name) }),
               let url = URL(string: asset.browserDownloadUrl) {
                let sha = parseDigest(asset.digest)
                    ?? (asset.name == dxvkFallback.filename ? dxvkFallback.sha256 : nil)
                    ?? dxvkFallback.sha256
                return ResolvedComponent(
                    name: "dxvk",
                    version: release.tagName,
                    url: url,
                    filename: asset.name,
                    sha256: sha
                )
            }
        }
        return dxvkFallback
    }

    public static func isLegendaryMacBinary(_ filename: String) -> Bool {
        let name = filename.lowercased()
        if name.contains("windows") || name.contains("linux") || name.hasSuffix(".exe") || name.hasSuffix(".deb") {
            return false
        }
        return name.contains("macos") && name.contains("arm64") && !name.hasSuffix(".zip")
    }

    public static func resolveLegendary() async -> ResolvedComponent {
        let fallback = legendaryFallback
        if let latest = try? await latestRelease(repo: legendaryRepo) {
            if let asset = latest.assets.first(where: { isLegendaryMacBinary($0.name) }),
               let url = URL(string: asset.browserDownloadUrl) {
                return ResolvedComponent(
                    name: fallback.name,
                    version: latest.tagName,
                    url: url,
                    filename: asset.name,
                    sha256: parseDigest(asset.digest) ?? fallback.sha256
                )
            }
        }
        return fallback
    }

    public static func parseDigest(_ digest: String?) -> String? {
        guard let digest, !digest.isEmpty else { return nil }
        if let idx = digest.firstIndex(of: ":") {
            let hash = String(digest[digest.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            return hash.isEmpty ? nil : hash.lowercased()
        }
        return digest.lowercased()
    }

    static func latestRelease(repo: String) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw DownloadError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.httpFailure(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    static func listReleases(repo: String, perPage: Int) async throws -> [GitHubRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=\(perPage)") else {
            throw DownloadError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.httpFailure(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GitHubRelease].self, from: data)
    }
}

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let assets: [GitHubAsset]
    let prerelease: Bool?
    let draft: Bool?

    var isOfferedStable: Bool {
        ComponentCatalog.isOfferedStableRelease(
            tagName: tagName,
            prerelease: prerelease ?? false,
            draft: draft ?? false,
            assetNames: assets.map(\.name)
        )
    }
}

struct GitHubAsset: Decodable, Sendable {
    let name: String
    let browserDownloadUrl: String
    let digest: String?
}
