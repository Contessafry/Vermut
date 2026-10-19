import XCTest
@testable import CaskLauncherCore

final class ComponentCatalogTests: XCTestCase {

    func testWineFallbackURLsPointAtUnderscoredRepo() {
        let staging = ComponentCatalog.wineStagingFallback
        XCTAssertEqual(staging.version, "11.18")
        XCTAssertTrue(staging.url.absoluteString.contains("Gcenx/macOS_Wine_builds"))
        XCTAssertTrue(staging.url.absoluteString.contains("wine-staging-11.18-osx64.tar.xz"))
        XCTAssertEqual(staging.sha256?.count, 64)

        let devel = ComponentCatalog.wineDevelFallback
        XCTAssertTrue(devel.url.absoluteString.contains("wine-devel-11.18-osx64.tar.xz"))
        XCTAssertFalse(devel.url.absoluteString.contains("macOS-Wine-builds"))
    }

    func testDXMTAndDXVKFallbackURLs() {
        XCTAssertTrue(ComponentCatalog.dxmtFallback.url.absoluteString.contains("3Shain/dxmt"))
        XCTAssertTrue(ComponentCatalog.dxmtFallback.filename.contains("v0.80"))
        XCTAssertTrue(ComponentCatalog.dxvkFallback.url.absoluteString.contains("Gcenx/DXVK-macOS"))
        XCTAssertTrue(ComponentCatalog.dxvkFallback.filename.contains("v1.10.3-20230507"))
        XCTAssertFalse(ComponentCatalog.dxvkFallback.filename.contains("builtin"))
        XCTAssertFalse(ComponentCatalog.dxvkFallback.filename.contains("repack"))
        XCTAssertEqual(
            ComponentCatalog.dxvkFallback.sha256,
            "f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516"
        )
        XCTAssertTrue(ComponentCatalog.isDXVKArchiveWithDxgi(ComponentCatalog.dxvkFallback.filename))
        XCTAssertFalse(ComponentCatalog.isDXVKArchiveWithDxgi(ComponentCatalog.dxvkBuiltinFallback.filename))
        XCTAssertTrue(ComponentCatalog.dxvkBuiltinFallback.filename.contains("builtin"))
    }

    func testLegendaryFallbackIsOfficialMacARMBinary() {
        let fallback = ComponentCatalog.legendaryFallback
        XCTAssertEqual(fallback.filename, "legendary_macOS_arm64")
        XCTAssertEqual(fallback.version, "0.21.1")
        XCTAssertTrue(fallback.url.absoluteString.contains("legendary-gl/legendary"))
        XCTAssertEqual(
            fallback.sha256,
            "d87978321dba9cb731fab40c72f0a30bed55baca8b5341ab21024c5733cd837e"
        )
        XCTAssertTrue(ComponentCatalog.isLegendaryMacBinary("legendary_macOS_arm64"))
        XCTAssertFalse(ComponentCatalog.isLegendaryMacBinary("legendary_macOS.zip"))
        XCTAssertFalse(ComponentCatalog.isLegendaryMacBinary("legendary_linux_x64"))
        XCTAssertFalse(ComponentCatalog.isLegendaryMacBinary("legendary_windows_x64.exe"))
        XCTAssertEqual(ComponentCatalog.legendaryRepo, "legendary-gl/legendary")
    }

    func testParseDigest() {
        XCTAssertEqual(
            ComponentCatalog.parseDigest("sha256:b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127"),
            "b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127"
        )
        XCTAssertNil(ComponentCatalog.parseDigest(nil))
        XCTAssertNil(ComponentCatalog.parseDigest(""))
        XCTAssertEqual(ComponentCatalog.parseDigest("ABCDEF"), "abcdef")
    }

    func testWineEngineCases() {
        XCTAssertEqual(WineEngine.allCases.map(\.rawValue), ["grapple-wine", "staging", "devel"])
        XCTAssertEqual(WineEngine.grappleWine.displayName, "Vermut Wine 11 (DXMT build)")
        XCTAssertEqual(WineEngine.staging.displayName, "Wine Staging 11")
        XCTAssertEqual(WineEngine.defaultEngine, .grappleWine)
        XCTAssertTrue(WineEngine.grappleWine.supportsDXMT)
        XCTAssertFalse(WineEngine.staging.supportsDXMT)
    }

    func testGrappleWineFallbackIsPinned() {
        let fallback = ComponentCatalog.grappleWineFallback
        XCTAssertEqual(fallback.filename, "grapple-wine-1.0.2.tar.xz")
        XCTAssertEqual(fallback.version, "1.0.2")
        XCTAssertTrue(fallback.url.absoluteString.contains("MartijnBud/grapple-releases"))
        XCTAssertTrue(fallback.url.absoluteString.contains("v0.2.5-beta.1"))
        XCTAssertEqual(
            fallback.sha256,
            "db4925788bef2f83404bb685e2304cb923d62c5759312ee639822aaf85b34a5c"
        )
        XCTAssertEqual(ComponentCatalog.fallback(for: .grappleWine).filename, fallback.filename)
        XCTAssertTrue(ComponentCatalog.isGrappleWineArchive("grapple-wine-1.0.2.tar.xz"))
        XCTAssertFalse(ComponentCatalog.isGrappleWineArchive("grapple-wine-1.0.2-source.tar.xz"))
        XCTAssertFalse(ComponentCatalog.isGrappleWineArchive("wine-staging-11.18-osx64.tar.xz"))
    }

    func testSHA256OfKnownFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cask-hash-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hex = try Checksum.sha256Hex(ofFile: url)
        XCTAssertEqual(hex, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

        XCTAssertThrowsError(try Checksum.verify(file: url, expectedHex: "00")) { error in
            guard case DownloadError.checksumMismatch = error else {
                return XCTFail("Expected checksum mismatch, got \(error)")
            }
        }
    }

    func testHTTPFailureMessageIncludesStatus() {
        let description = DownloadError.httpFailure(404).localizedDescription
        XCTAssertTrue(description.contains("404"))
    }

    func testCachedFileIsValidWhenHashMatches() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cask-cache-\(UUID().uuidString).bin")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertTrue(DownloadClient.cachedFileIsValid(at: url, expectedSHA256: hash))
        XCTAssertFalse(DownloadClient.cachedFileIsValid(at: url, expectedSHA256: "00" + String(repeating: "ab", count: 31)))
        XCTAssertTrue(DownloadClient.cachedFileIsValid(at: url, expectedSHA256: nil))
        XCTAssertFalse(DownloadClient.cachedFileIsValid(
            at: url.deletingLastPathComponent().appendingPathComponent("missing.bin"),
            expectedSHA256: hash
        ))
    }

    func testDownloadSkipsNetworkWhenCacheHashMatches() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cask-skip-\(UUID().uuidString).bin")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let progressBox = ProgressBox()
        // A guaranteed-missing URL: this would throw if the cache were not reused.
        try await DownloadClient.download(
            from: URL(string: "https://127.0.0.1:1/does-not-exist")!,
            to: url,
            expectedSHA256: hash,
            progress: { value in
                progressBox.value = value
            }
        )
        XCTAssertEqual(progressBox.value, 1.0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }
}

private final class ProgressBox: @unchecked Sendable {
    var value: Double = 0
}
