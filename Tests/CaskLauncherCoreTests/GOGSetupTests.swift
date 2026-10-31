import XCTest
@testable import CaskLauncherCore

final class GOGSetupTests: XCTestCase {
    func testHungInstallerWithPayloadIsSuccessNotTimeout() {
        XCTAssertTrue(GOGInstallAcceptance.acceptInstallerResult(timedOut: true, payloadInstalled: true))
        XCTAssertNil(GOGInstallAcceptance.wineError(timedOut: true, payloadInstalled: true, store: .gog))

        XCTAssertFalse(GOGInstallAcceptance.acceptInstallerResult(timedOut: true, payloadInstalled: false))
        XCTAssertEqual(
            GOGInstallAcceptance.wineError(timedOut: true, payloadInstalled: false, store: .gog)?.errorDescription,
            WineError.installerTimedOut(.gog).errorDescription
        )

        XCTAssertTrue(GOGInstallAcceptance.acceptInstallerResult(timedOut: false, payloadInstalled: true))
        XCTAssertNil(GOGInstallAcceptance.wineError(timedOut: false, payloadInstalled: false, store: .gog))
    }

    func testWatchFinishesAfterPayloadGraceWithoutLeftovers() {
        XCTAssertEqual(
            GOGSetupWatch.decide(
                payloadInstalled: false,
                installerRunning: true,
                secondsSincePayloadSeen: nil,
                leftoverCount: 0
            ),
            .wait
        )
        XCTAssertEqual(
            GOGSetupWatch.decide(
                payloadInstalled: true,
                installerRunning: true,
                secondsSincePayloadSeen: 1,
                leftoverCount: 2
            ),
            .stopLeftovers
        )
        XCTAssertEqual(
            GOGSetupWatch.decide(
                payloadInstalled: true,
                installerRunning: true,
                secondsSincePayloadSeen: 1,
                leftoverCount: 0
            ),
            .wait
        )
        XCTAssertEqual(
            GOGSetupWatch.decide(
                payloadInstalled: true,
                installerRunning: true,
                secondsSincePayloadSeen: GOGSetupWatch.postPayloadGrace,
                leftoverCount: 0
            ),
            .finishBecausePayloadInstalled
        )
        XCTAssertEqual(
            GOGSetupWatch.decide(
                payloadInstalled: true,
                installerRunning: false,
                secondsSincePayloadSeen: 0,
                leftoverCount: 0
            ),
            .finishBecausePayloadInstalled
        )
    }

    func testLeftoversIncludeGalaxyClientWithoutFirstRun() {
        let prefix = "/Users/u/Library/Application Support/Vermut/bottles/gog/prefix"
        let lines = [
            "  4911 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe /firstRun /installationSource=usedefault WINEPREFIX=\(prefix) HOME=/Users/u",
            "  4912 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe WINEPREFIX=\(prefix) HOME=/Users/u",
            "  4913 C:\\Program Files\\GOG Galaxy\\GalaxyClient.exe /firstRun WINEPREFIX=/other/prefix HOME=/Users/u",
            "  4914 C:\\setup_galaxy.tmp /SL5 WINEPREFIX=\(prefix)"
        ]
        XCTAssertEqual(GOGSetupLeftovers.pids(in: lines, prefixPath: prefix), [4911, 4912])
        XCTAssertEqual(GOGFirstRun.pids(in: lines, prefixPath: prefix), [4911])
    }

    func testSilentInstallerClosesLeftoverApplications() {
        let args = StoreInstaller.wineArguments(installerHostPath: "/tmp/setup_galaxy.exe", store: .gog)
        XCTAssertTrue(args.contains("/CLOSEAPPLICATIONS"))
        XCTAssertTrue(args.contains("/FORCECLOSEAPPLICATIONS"))
        XCTAssertTrue(args.contains("/VERYSILENT"))
        XCTAssertEqual(StoreInstaller.timeout(for: .gog), 15 * 60)
    }
}

final class GOGSoftwareRendererTests: XCTestCase {
    func testRecipeRequiresSoftwareRendererFiles() {
        XCTAssertEqual(GOGSoftwareRenderer.requiredFilenames, ["opengl32sw.dll", "libgallium_wgl.dll"])
        XCTAssertEqual(GOGRecipe.softwareEnvironment["GALLIUM_DRIVER"], "llvmpipe")
        XCTAssertEqual(GOGRecipe.softwareEnvironment["QT_OPENGL"], "software")
    }

    func testLaunchRecipePinsGalliumLlvmpipe() {
        let recipe = StoreLaunchRecipe.build(
            store: .gog,
            executable: URL(fileURLWithPath: "/prefix/drive_c/Program Files/GOG Galaxy/GalaxyClient.exe"),
            wineLibDir: URL(fileURLWithPath: "/engines/staging/lib/wine")
        )
        XCTAssertEqual(recipe.environment["GALLIUM_DRIVER"], "llvmpipe")
        XCTAssertEqual(recipe.environment["QT_OPENGL"], "software")
    }

    func testInstallCopiesMesaLoaderAsOpengl32sw() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gog-mesa-\(UUID().uuidString)", isDirectory: true)
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("gog-prefix-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: prefix)
        }

        let x64 = root.appendingPathComponent("x64", isDirectory: true)
        try FileManager.default.createDirectory(at: x64, withIntermediateDirectories: true)
        try Data("mesa-opengl32".utf8).write(to: x64.appendingPathComponent("opengl32.dll"))
        try Data("mesa-gallium".utf8).write(to: x64.appendingPathComponent("libgallium_wgl.dll"))

        let exe = prefix.appendingPathComponent("drive_c/Program Files/GOG Galaxy/GalaxyClient.exe")
        try FileManager.default.createDirectory(
            at: exe.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("galaxy".utf8).write(to: exe)

        XCTAssertFalse(GOGSoftwareRenderer.isInstalled(beside: exe))
        XCTAssertEqual(GOGSoftwareRenderer.missingRequired(beside: exe), GOGSoftwareRenderer.requiredFilenames)

        try GOGSoftwareRenderer.install(fromExtractedMesa: root, beside: exe)

        XCTAssertTrue(GOGSoftwareRenderer.isInstalled(beside: exe))
        XCTAssertTrue(GOGSoftwareRenderer.missingRequired(beside: exe).isEmpty)
        let dest = exe.deletingLastPathComponent()
        XCTAssertEqual(
            try String(contentsOf: dest.appendingPathComponent("opengl32sw.dll"), encoding: .utf8),
            "mesa-opengl32"
        )
        XCTAssertEqual(
            try String(contentsOf: dest.appendingPathComponent("libgallium_wgl.dll"), encoding: .utf8),
            "mesa-gallium"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("opengl32.dll").path))
    }

    func testMesaAndSevenZipArePinned() {
        let mesa = ComponentCatalog.mesaDistWinFallback
        XCTAssertEqual(mesa.name, "mesa-dist-win")
        XCTAssertEqual(mesa.version, "26.2.5")
        XCTAssertEqual(mesa.filename, "mesa3d-26.2.5-release-msvc.7z")
        XCTAssertEqual(
            mesa.sha256,
            "997123ef4ce8896204ab912d5b54f19372c487ff9835bcefafa2fca23b8953c2"
        )
        XCTAssertTrue(mesa.url.absoluteString.contains("pal1000/mesa-dist-win"))
        XCTAssertTrue(mesa.url.absoluteString.contains("mesa3d-26.2.5-release-msvc.7z"))

        let seven = ComponentCatalog.sevenZipMacFallback
        XCTAssertEqual(seven.filename, "7z2501-mac.tar.xz")
        XCTAssertEqual(seven.version, "25.01")
        XCTAssertEqual(
            seven.sha256,
            "26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0"
        )
        XCTAssertTrue(seven.url.absoluteString.contains("7-zip.org"))
        XCTAssertEqual(
            SevenZipTool.extractArguments(
                archive: URL(fileURLWithPath: "/tmp/mesa.7z"),
                destination: URL(fileURLWithPath: "/tmp/out")
            ),
            ["x", "-y", "-o/tmp/out", "/tmp/mesa.7z"]
        )
    }
}
