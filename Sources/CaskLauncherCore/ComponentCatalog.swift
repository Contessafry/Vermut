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

    static func resolveGcenxWine(_ engine: WineEngine) async -> ResolvedComponent {
        let fallback = fallback(for: engine)
        if let latest = try? await latestRelease(repo: wineRepo) {
            let prefix = engine.githubAssetPrefix
            if let asset = latest.assets.first(where: {
                $0.name.hasPrefix(prefix) && $0.name.hasSuffix("-osx64.tar.xz")
            }), let url = URL(string: asset.browserDownloadUrl) {
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

    public static func resolveDXMT() async -> ResolvedComponent {
        if let latest = try? await latestRelease(repo: dxmtRepo) {
            let asset = latest.assets.first(where: { $0.name.contains("builtin") && $0.name.hasSuffix(".tar.gz") })
                ?? latest.assets.first(where: { $0.name.hasSuffix(".tar.gz") })
            if let asset, let url = URL(string: asset.browserDownloadUrl) {
                return ResolvedComponent(
                    name: "dxmt",
                    version: latest.tagName,
                    url: url,
                    filename: asset.name,
                    sha256: parseDigest(asset.digest) ?? dxmtFallback.sha256
                )
            }
        }
        return dxmtFallback
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
}

struct GitHubAsset: Decodable, Sendable {
    let name: String
    let browserDownloadUrl: String
    let digest: String?
}
