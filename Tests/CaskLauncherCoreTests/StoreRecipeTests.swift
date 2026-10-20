import XCTest
@testable import CaskLauncherCore

final class StoreRecipeTests: XCTestCase {

    func testEpicDetectsLauncherUnderProgramFilesWin64() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let x86 = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: x86.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: prefix.appendingPathComponent(GameStore.epic.executablePath).path
            )
        )

        let win64 = prefix.appendingPathComponent(
            "drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        )
        try touch(win64)

        let resolved = StoreExecutable.resolve(in: prefix, store: .epic)
        XCTAssertEqual(resolved?.path, win64.path)
        XCTAssertTrue(resolved!.path.contains("Program Files/Epic Games"))
        XCTAssertTrue(resolved!.path.contains("Win64"))
        XCTAssertFalse(resolved!.path.contains("Program Files (x86)"))
    }

    func testEpicPrefersWin64OverWin32() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let win64 = prefix.appendingPathComponent(
            "drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        )
        let win32 = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe"
        )
        try touch(win64)
        try touch(win32)

        let candidates = StoreExecutable.launchCandidates(in: prefix, store: .epic)
        XCTAssertEqual(candidates.first?.path, win64.path)
        XCTAssertTrue(StoreExecutable.isWin64(candidates[0]))
        XCTAssertTrue(candidates.contains(where: { StoreExecutable.isWin32($0) }))
        XCTAssertEqual(StoreExecutable.resolve(in: prefix, store: .epic)?.path, win64.path)
    }

    func testEpicFindsNestedWin64WhenThatIsAllThatExists() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let nested = prefix.appendingPathComponent(
            "drive_c/Program Files/Epic Games/EpicGamesLauncher/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
        )
        try touch(nested)
        let resolved = StoreExecutable.resolve(in: prefix, store: .epic)
        XCTAssertEqual(resolved?.lastPathComponent, "EpicGamesLauncher.exe")
        XCTAssertTrue(resolved!.path.contains("Win64"))
    }

    func testSteamStillResolvesX86PathFirst() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let x86 = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steam.exe"
        )
        try touch(x86)
        try touch(prefix.appendingPathComponent("drive_c/Program Files/Steam/steam.exe"))

        let resolved = StoreExecutable.resolve(in: prefix, store: .steam)
        XCTAssertEqual(resolved?.path, x86.path)
    }

    func testGOGResolvesProgramFilesGalaxyClient() throws {
        let prefix = try makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let exe = prefix.appendingPathComponent(
            "drive_c/Program Files/GOG Galaxy/GalaxyClient.exe"
        )
        try touch(exe)
        XCTAssertEqual(StoreExecutable.resolve(in: prefix, store: .gog)?.path, exe.path)
    }

    func testInstallerArgumentsByStore() {
        let steam = StoreInstaller.wineArguments(installerHostPath: "/tmp/SteamSetup.exe", store: .steam)
        XCTAssertEqual(steam, ["/tmp/SteamSetup.exe", "/S"])

        let epic = StoreInstaller.wineArguments(installerHostPath: "/tmp/Epic.msi", store: .epic)
        XCTAssertEqual(epic, [])

        let gog = StoreInstaller.wineArguments(installerHostPath: "/tmp/setup_galaxy.exe", store: .gog)
        XCTAssertEqual(
            gog,
            [
                "/tmp/setup_galaxy.exe",
                "/VERYSILENT",
                "/SUPPRESSMSGBOXES",
                "/NORESTART",
                "/SP-"
            ]
        )
        XCTAssertFalse(gog.contains("/S"))
        XCTAssertEqual(StoreInstaller.timeout(for: .steam), nil)
        XCTAssertEqual(StoreInstaller.timeout(for: .epic), 15 * 60)
        XCTAssertEqual(StoreInstaller.timeout(for: .gog), 15 * 60)
    }

    func testGOGDownloadIsOfflineSetupNotWebStub() {
        XCTAssertTrue(StoreInstaller.downloadURL(for: .gog).contains("setup_galaxy"))
        XCTAssertTrue(StoreInstaller.filename(for: .gog).contains("setup_galaxy"))
        XCTAssertFalse(StoreInstaller.downloadURL(for: .gog).contains("GOG_Galaxy_2.0.exe"))
        XCTAssertFalse(StoreInstaller.downloadURL(for: .gog).contains("webinstallers.gog-statics.com"))
        XCTAssertEqual(GameStore.gog.installerURL, StoreInstaller.downloadURL(for: .gog))
        XCTAssertEqual(GameStore.gog.installerFilename, StoreInstaller.filename(for: .gog))
    }

    func testParsesGOGRemoteConfigWindowsLink() {
        let json = #"{"version":"2.0.0","content":{"windows":{"size":342291968,"version":"2.1.10.56","deprecated":false,"downloadLink":"https:\/\/content-system.gog.com\/open_link\/download?path=\/open\/galaxy\/client\/setup_galaxy_2.1.10.56.exe"}}}"#
        let parsed = StoreInstaller.parseGOGWindowsInstaller(fromJSON: json)
        XCTAssertEqual(parsed?.filename, "setup_galaxy_2.1.10.56.exe")
        XCTAssertEqual(
            parsed?.url.absoluteString,
            "https://content-system.gog.com/open_link/download?path=/open/galaxy/client/setup_galaxy_2.1.10.56.exe"
        )
        XCTAssertNil(
            StoreInstaller.parseGOGWindowsInstaller(
                fromJSON: #"{"content":{"windows":{"downloadLink":"https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe"}}}"#
            )
        )
    }

    func testEpicBottleUsesAppGraphicsAndStagingForDXVK() {
        let app = AppConfiguration(
            defaultEngine: WineEngine.grappleWine.rawValue,
            defaultGraphicsBackend: GraphicsBackend.dxmt.rawValue,
            enableHiDPI: true,
            windowsVersion: "win7"
        )
        let steam = StoreRecipe.bottleConfiguration(from: app, for: .steam)
        XCTAssertEqual(steam.graphicsBackend, GraphicsBackend.dxmt.rawValue)
        XCTAssertFalse(steam.enableHiDPI)
        XCTAssertEqual(steam.windowsVersion, "win10")

        let epic = StoreRecipe.bottleConfiguration(from: app, for: .epic)
        XCTAssertEqual(epic.engine, WineEngine.grappleWine.rawValue)
        XCTAssertEqual(epic.graphicsBackend, GraphicsBackend.dxmt.rawValue)
        XCTAssertFalse(epic.enableHiDPI)
        XCTAssertEqual(epic.windowsVersion, "win10")
        let dxvkOnGrapple = StoreRecipe.normalized(
            BottleConfiguration(
                engine: WineEngine.grappleWine.rawValue,
                graphicsBackend: GraphicsBackend.dxvk.rawValue
            ),
            for: .epic
        )
        XCTAssertEqual(dxvkOnGrapple.engine, WineEngine.staging.rawValue)
        XCTAssertEqual(dxvkOnGrapple.graphicsBackend, GraphicsBackend.dxvk.rawValue)
        XCTAssertTrue(StoreRecipe.allowsNativeGraphics(.epic))
        XCTAssertFalse(StoreRecipe.allowsNativeGraphics(.gog))
        XCTAssertTrue(StoreRecipe.allowsNativeGraphics(.steam))

        let gog = StoreRecipe.bottleConfiguration(from: app, for: .gog)
        XCTAssertEqual(gog.graphicsBackend, GraphicsBackend.wined3d.rawValue)
    }

    func testInstallerTimedOutErrorIsActionable() {
        let message = WineError.installerTimedOut(.gog).errorDescription ?? ""
        XCTAssertTrue(message.contains("GOG"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("time"))
        XCTAssertFalse(message.isEmpty)
    }

    func testDllOverrideSummaryIsPlainLanguage() {
        let steam = DllOverridePolicy.userFacingSummary(
            engine: .grappleWine,
            backend: .dxmt,
            store: .steam
        )
        XCTAssertEqual(steam, "Engine default")
        let epic = DllOverridePolicy.userFacingSummary(
            engine: .grappleWine,
            backend: .dxvk,
            store: .epic
        )
        XCTAssertEqual(epic, "DXVK native, Vulkan built-in")
        XCTAssertTrue(epic.localizedCaseInsensitiveContains("vulkan"))
        XCTAssertFalse(epic.localizedCaseInsensitiveContains("cef"))
        XCTAssertFalse(epic.localizedCaseInsensitiveContains("grapple"))
        XCTAssertTrue(WineError.cancelled.isCancelled)
        XCTAssertEqual(WineError.cancelled.errorDescription, "Installation cancelled")
    }

    private func makePrefix() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-prefix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
    }

    func testGOGIsComingSoonOthersAvailable() {
        XCTAssertTrue(StoreRecipe.isComingSoon(.gog))
        XCTAssertFalse(StoreRecipe.isComingSoon(.steam))
        XCTAssertFalse(StoreRecipe.isComingSoon(.epic))
    }

    func testFirstSetupSelectionDropsComingSoonStores() {
        XCTAssertEqual(StoreRecipe.selectableStores([.steam, .epic, .gog]), [.steam, .epic])
    }
}
