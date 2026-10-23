import XCTest
@testable import CaskLauncherCore

final class DXMTVersionManagerTests: XCTestCase {
    func testDefaultVersionIsV080() {
        XCTAssertEqual(DXMTVersionManager.defaultVersionTag, "v0.80")
        XCTAssertEqual(ComponentCatalog.dxmtFallback.version, "v0.80")
        XCTAssertTrue(ComponentCatalog.dxmtFallback.filename.contains("v0.80"))
    }

    func testVisibleRemoteKeepsLatestPlusFivePrevious() {
        let manager = DXMTVersionManager()
        let remote: [ResolvedComponent] = (0..<8).map { index in
            let tag = "v0.\(80 - index)"
            return ResolvedComponent(
                name: "dxmt",
                version: tag,
                url: ComponentCatalog.dxmtFallback.url,
                filename: "dxmt-\(tag)-builtin.tar.gz",
                sha256: nil
            )
        }
        let visible = manager.visibleRemoteTags(from: remote, defaultTag: "v0.80", installed: [])
        // Newest + 5 previous = 6 entries when default is newest.
        XCTAssertEqual(visible.count, 6)
        XCTAssertEqual(ComponentVersion.canonicalTag(visible[0].version), "v0.80")
        XCTAssertEqual(ComponentVersion.canonicalTag(visible[5].version), "v0.75")
    }

    func testVisibleRemoteKeepsInstalledOutsideWindow() {
        // Remote window is newest + 5 previous (indices 0…5 → v0.80…v0.75).
        // v0.73 is in the remote list but outside that window; installed must keep it.
        let manager = DXMTVersionManager()
        let remote: [ResolvedComponent] = (0..<8).map { index in
            let tag = "v0.\(80 - index)"
            return ResolvedComponent(
                name: "dxmt",
                version: tag,
                url: ComponentCatalog.dxmtFallback.url,
                filename: "dxmt-\(tag)-builtin.tar.gz",
                sha256: nil
            )
        }
        let visible = manager.visibleRemoteTags(
            from: remote,
            defaultTag: "v0.80",
            installed: ["v0.73"]
        )
        XCTAssertTrue(visible.contains { ComponentVersion.canonicalTag($0.version) == "v0.73" })
        XCTAssertGreaterThanOrEqual(visible.count, 7)
    }

    func testMergeCatalogMarksDefaultAndSuggestsNewer() {
        let manager = DXMTVersionManager()
        let remote = [
            ResolvedComponent(
                name: "dxmt",
                version: "v0.81",
                url: ComponentCatalog.dxmtFallback.url,
                filename: "dxmt-v0.81-builtin.tar.gz",
                sha256: nil
            ),
            ComponentCatalog.dxmtFallback
        ]
        let merged = manager.mergeCatalog(remote: remote, installed: ["v0.80"], defaultTag: "v0.80")
        XCTAssertTrue(merged.contains { $0.tag == "v0.80" && $0.isDefault })
        let suggestion = manager.newerThanDefault(in: merged, defaultTag: "v0.80")
        XCTAssertEqual(suggestion?.tag, "v0.81")
    }

    func testIsDXMTArchiveHelpers() {
        XCTAssertTrue(ComponentCatalog.isDXMTBuiltinArchive("dxmt-v0.80-builtin.tar.gz"))
        XCTAssertTrue(ComponentCatalog.isDXMTArchive("dxmt-v0.70.tar.gz"))
        XCTAssertFalse(ComponentCatalog.isDXMTArchive("dxmt-v0.80-source.tar.gz"))
        XCTAssertFalse(ComponentCatalog.isDXMTBuiltinArchive("dxvk-macOS.tar.gz"))
    }

    func testInstallURLUsesCanonicalTag() {
        let manager = DXMTVersionManager()
        let url = manager.installURL(for: "0.80")
        XCTAssertTrue(url.path.contains("/versions/v0.80"))
    }
}
