import XCTest
@testable import CaskLauncherCore

final class EngineLayoutTests: XCTestCase {
    var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cask-layout-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        super.tearDown()
    }

    func testGcenxAppBundleLayout() throws {
        let install = tempRoot.appendingPathComponent("staging")
        try writeGcenxTree(at: install, appName: "Wine Staging.app")

        let layout = EngineLayout.resolve(installRoot: install)
        XCTAssertNotNil(layout)
        XCTAssertEqual(
            layout?.wineExecutable.lastPathComponent,
            "wine"
        )
        XCTAssertTrue(layout!.wineExecutable.path.hasSuffix("Contents/Resources/wine/bin/wine"))
        XCTAssertTrue(layout!.wineserverExecutable.path.hasSuffix("Contents/Resources/wine/bin/wineserver"))
        XCTAssertTrue(layout!.wineRoot.path.hasSuffix("Contents/Resources/wine"))
        XCTAssertTrue(layout!.wineLibDir.path.hasSuffix("lib/wine"))
        XCTAssertNotNil(layout?.windows64Dir)
        XCTAssertNotNil(layout?.windows32Dir)
        XCTAssertNotNil(layout?.unix64Dir)
        XCTAssertTrue(layout!.windows64Dir!.path.hasSuffix("x86_64-windows"))
    }

    func testDevelAppBundleLayout() throws {
        let install = tempRoot.appendingPathComponent("devel")
        try writeGcenxTree(at: install, appName: "Wine Devel.app")

        let layout = EngineLayout.resolve(installRoot: install)
        XCTAssertTrue(layout!.wineExecutable.path.contains("Wine Devel.app"))
        XCTAssertEqual(layout?.wineserverExecutable.lastPathComponent, "wineserver")
    }

    func testStrippedContentsLayout() throws {
        let install = tempRoot.appendingPathComponent("stripped")
        try touch(install.appendingPathComponent("Contents/Resources/wine/bin/wine"))
        try touch(install.appendingPathComponent("Contents/Resources/wine/bin/wineserver"))
        try touch(install.appendingPathComponent("Contents/MacOS/wine"))

        let layout = EngineLayout.resolve(installRoot: install)
        XCTAssertTrue(layout!.wineRoot.path.hasSuffix("Contents/Resources/wine"))
        XCTAssertTrue(layout!.wineExecutable.path.hasSuffix("bin/wine"))
    }

    func testGrappleWineNestedLayoutAndBundledDXMT() throws {
        let install = tempRoot.appendingPathComponent("grapple-wine")
        try touch(install.appendingPathComponent("grapple-wine/bin/wine"))
        try touch(install.appendingPathComponent("grapple-wine/bin/wineserver"))
        try write(install.appendingPathComponent("grapple-wine/lib/wine/x86_64-windows/d3d11.dll"), "wined3d-d3d11")
        try write(install.appendingPathComponent("grapple-wine/lib/wine/x86_64-windows/dxgi.dll"), "wined3d-dxgi")
        try touch(install.appendingPathComponent("grapple-wine/lib/wine/x86_64-unix/winemac.so"))
        try write(install.appendingPathComponent("grapple-wine/share/grapple/dxmt/x86_64-windows/d3d11.dll"), "dxmt-d3d11")
        try write(install.appendingPathComponent("grapple-wine/share/grapple/dxmt/x86_64-windows/dxgi.dll"), "dxmt-dxgi")
        try write(install.appendingPathComponent("grapple-wine/share/grapple/dxmt/x86_64-windows/d3d10core.dll"), "dxmt-d3d10core")
        try write(install.appendingPathComponent("grapple-wine/share/grapple/dxmt/x86_64-windows/winemetal.dll"), "dxmt-winemetal")
        try touch(install.appendingPathComponent("grapple-wine/share/grapple/dxmt/x86_64-unix/winemetal.so"))

        let layout = EngineLayout.resolve(installRoot: install)
        XCTAssertNotNil(layout)
        XCTAssertTrue(layout!.wineRoot.path.hasSuffix("grapple-wine/grapple-wine"))
        XCTAssertTrue(layout!.wineExecutable.path.hasSuffix("grapple-wine/bin/wine"))
        XCTAssertTrue(layout!.wineLibDir.path.hasSuffix("lib/wine"))
        XCTAssertNotNil(layout?.unix64Dir)

        let bundled = layout!.bundledDXMTOverlay()
        XCTAssertNotNil(bundled)
        XCTAssertTrue(bundled!.hasD3D11)
        XCTAssertNotNil(bundled?.unix64Dir)
        XCTAssertTrue(DXMTUnixLib.needsInstall(overlay: bundled!, engine: layout!))
        try DXMTUnixLib.installIfNeeded(overlay: bundled!, engine: layout!)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: layout!.unix64Dir!.appendingPathComponent("winemetal.so").path
            )
        )

        XCTAssertTrue(DXMTWindowsDLLs.needsInstall(overlay: bundled!, engine: layout!))
        try DXMTWindowsDLLs.installIntoEngine(overlay: bundled!, engine: layout!)
        XCTAssertFalse(DXMTWindowsDLLs.needsInstall(overlay: bundled!, engine: layout!))
        let win64 = layout!.windows64Dir!
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("d3d11.dll"), encoding: .utf8), "dxmt-d3d11")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("dxgi.dll"), encoding: .utf8), "dxmt-dxgi")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("d3d10core.dll"), encoding: .utf8), "dxmt-d3d10core")
        XCTAssertEqual(try String(contentsOf: win64.appendingPathComponent("winemetal.dll"), encoding: .utf8), "dxmt-winemetal")
    }

    func testFlatBinLayout() throws {
        let install = tempRoot.appendingPathComponent("flat")
        try touch(install.appendingPathComponent("bin/wine"))
        try touch(install.appendingPathComponent("bin/wineserver"))
        try touch(install.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"))

        let layout = EngineLayout.resolve(installRoot: install)
        XCTAssertEqual(layout?.wineRoot.path, install.path)
        XCTAssertTrue(layout!.wineExecutable.path.hasSuffix("bin/wine"))
        XCTAssertNotNil(layout?.windows64Dir)
    }

    func testMissingWineReturnsNil() throws {
        let install = tempRoot.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        XCTAssertNil(EngineLayout.resolve(installRoot: install))
    }

    func testValidEngineTreeIsConsideredInstalled() throws {
        let install = tempRoot.appendingPathComponent("already-installed")
        try writeGcenxTree(at: install, appName: "Wine Staging.app")
        XCTAssertNotNil(EngineLayout.resolve(installRoot: install), "setup should skip re-extraction")
    }

    func testDXMTVersionedOverlay() throws {
        let install = tempRoot.appendingPathComponent("dxmt")
        try touch(install.appendingPathComponent("v0.80/x86_64-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("v0.80/x86_64-windows/dxgi.dll"))
        try touch(install.appendingPathComponent("v0.80/x86_64-windows/winemetal.dll"))
        try touch(install.appendingPathComponent("v0.80/i386-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("v0.80/x86_64-unix/winemetal.so"))

        let overlay = OverlayLayout.resolve(installRoot: install)
        XCTAssertNotNil(overlay)
        XCTAssertTrue(overlay!.root.path.hasSuffix("v0.80"))
        XCTAssertTrue(overlay!.hasD3D11)
        XCTAssertNotNil(overlay?.unix64Dir)
        XCTAssertNotNil(overlay?.windows32Dir)
    }

    func testDXMTStoreSkipsVersionsChildWhenFlatOverlayPresent() throws {
        // Classic engines/dxmt layout beside engines/dxmt/versions/<tag> must keep the flat root.
        let install = tempRoot.appendingPathComponent("dxmt")
        try touch(install.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("x86_64-windows/dxgi.dll"))
        try touch(install.appendingPathComponent("versions/v0.80/x86_64-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("versions/v0.80/x86_64-windows/dxgi.dll"))

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: install))
        XCTAssertEqual(overlay.root.path, install.path)
        XCTAssertFalse(overlay.root.path.contains("/versions/"))
    }

    func testDXVKNamedOverlay() throws {
        let install = tempRoot.appendingPathComponent("dxvk")
        try touch(install.appendingPathComponent("dxvk-macOS-async-v1.10.3-20230507-repack-builtin/x86_64-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("dxvk-macOS-async-v1.10.3-20230507-repack-builtin/x86_64-windows/dxgi.dll"))
        try touch(install.appendingPathComponent("dxvk-macOS-async-v1.10.3-20230507-repack-builtin/i386-windows/d3d11.dll"))

        let overlay = OverlayLayout.resolve(installRoot: install)
        XCTAssertTrue(overlay!.root.lastPathComponent.contains("dxvk-macOS-async"))
        XCTAssertTrue(overlay!.hasD3D11)
        XCTAssertTrue(overlay!.hasDXGI)
        XCTAssertTrue(overlay!.dxgiURL!.path.hasSuffix("x86_64-windows/dxgi.dll"))
    }

    func testBuiltinOverlayInstallsDxgiFromX64Pack() throws {
        let install = tempRoot.appendingPathComponent("dxvk-builtin")
        try touch(install.appendingPathComponent("x86_64-windows/d3d11.dll"))
        try touch(install.appendingPathComponent("x86_64-windows/d3d10core.dll"))
        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: install))
        XCTAssertTrue(overlay.hasD3D11)
        XCTAssertFalse(overlay.hasDXGI)

        let packDxgi = tempRoot.appendingPathComponent("x64-pack/dxgi.dll")
        try FileManager.default.createDirectory(at: packDxgi.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("dxvk-macos-1.10.3-x64-dxgi".utf8).write(to: packDxgi)
        try overlay.installWindowsDLL(packDxgi, named: "dxgi.dll")

        let updated = try XCTUnwrap(OverlayLayout.resolve(installRoot: install))
        XCTAssertTrue(updated.hasDXGI)
        XCTAssertEqual(
            try String(contentsOf: updated.windowsDLL("dxgi.dll")!, encoding: .utf8),
            "dxvk-macos-1.10.3-x64-dxgi"
        )
        XCTAssertTrue(updated.windowsDLL("dxgi.dll")!.path.contains("x86_64-windows"))
    }

    func testDXVKMacOSX64OverlayResolvesDxgi() throws {
        let install = tempRoot.appendingPathComponent("dxvk-x64")
        try touch(install.appendingPathComponent("x64/d3d11.dll"))
        try touch(install.appendingPathComponent("x64/d3d10core.dll"))
        try touch(install.appendingPathComponent("x64/dxgi.dll"))
        try touch(install.appendingPathComponent("x32/d3d11.dll"))

        let overlay = try XCTUnwrap(OverlayLayout.resolve(installRoot: install))
        XCTAssertEqual(overlay.root.path, install.path)
        XCTAssertTrue(overlay.windows64Dir!.path.hasSuffix("/x64"))
        XCTAssertTrue(overlay.hasD3D11)
        XCTAssertTrue(overlay.hasDXGI)
        XCTAssertTrue(overlay.dxgiURL!.path.hasSuffix("x64/dxgi.dll"))
        XCTAssertEqual(
            overlay.windowsDLL("dxgi.dll")?.path,
            install.appendingPathComponent("x64/dxgi.dll").path
        )
        XCTAssertTrue(
            overlay.windows64SearchDirectories().contains {
                $0.standardizedFileURL.path == install.appendingPathComponent("x64").standardizedFileURL.path
            }
        )
    }

    func testLauncherBinaryPrefersWine64ForWin64Epic() throws {
        let install = tempRoot.appendingPathComponent("staging")
        try writeGcenxTree(at: install, appName: "Wine Staging.app")
        let wineRoot = install.appendingPathComponent("Wine Staging.app/Contents/Resources/wine")
        try touch(wineRoot.appendingPathComponent("bin/wine64"))
        try touch(install.appendingPathComponent("Wine Staging.app/Contents/MacOS/wine64"))

        let layout = try XCTUnwrap(EngineLayout.resolve(installRoot: install))
        XCTAssertEqual(layout.wineExecutable.lastPathComponent, "wine")
        XCTAssertEqual(layout.wine64Executable?.lastPathComponent, "wine64")
        XCTAssertTrue(layout.wine64Executable!.path.hasSuffix("bin/wine64"))

        let epic = URL(
            fileURLWithPath: "/prefix/drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        )
        XCTAssertTrue(StoreExecutable.isWin64(epic))
        XCTAssertEqual(layout.launcherBinary(forWindowsExecutable: epic).lastPathComponent, "wine64")

        let steam = URL(fileURLWithPath: "/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        XCTAssertFalse(StoreExecutable.isWin64(steam))
        XCTAssertEqual(layout.launcherBinary(forWindowsExecutable: steam).lastPathComponent, "wine")
    }

    func testWineBinaryNotFoundMessageIncludesPath() {
        let message = EngineError.wineBinaryNotFound("/tmp/engines/staging").localizedDescription
        XCTAssertTrue(message.contains("/tmp/engines/staging"))
        XCTAssertFalse(message.contains("Failed to extract archive"))
        XCTAssertTrue(EngineError.extractionFailed.localizedDescription.contains("tar"))
        let missing = EngineError.overlayFileMissing("DXMT", "winemetal.dll", "/tmp/dxmt").localizedDescription
        XCTAssertTrue(missing.contains("winemetal.dll"))
        XCTAssertTrue(missing.contains("/tmp/dxmt"))
    }

    private func writeGcenxTree(at install: URL, appName: String) throws {
        let wineRoot = install.appendingPathComponent("\(appName)/Contents/Resources/wine")
        try touch(install.appendingPathComponent("\(appName)/Contents/MacOS/wine"))
        try touch(wineRoot.appendingPathComponent("bin/wine"))
        try touch(wineRoot.appendingPathComponent("bin/wineserver"))
        try touch(wineRoot.appendingPathComponent("bin/wineboot"))
        try touch(wineRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"))
        try touch(wineRoot.appendingPathComponent("lib/wine/i386-windows/d3d11.dll"))
        try touch(wineRoot.appendingPathComponent("lib/wine/x86_64-unix/wine"))
        try FileManager.default.createDirectory(
            at: install.appendingPathComponent("\(appName)/Contents"),
            withIntermediateDirectories: true
        )
        try Data("plist".utf8).write(to: install.appendingPathComponent("\(appName)/Contents/Info.plist"))
    }

    private func touch(_ url: URL) throws {
        try write(url, "x")
    }

    private func write(_ url: URL, _ contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}
