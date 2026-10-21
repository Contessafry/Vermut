import XCTest
@testable import CaskLauncherCore

final class SteamGameLaunchTests: XCTestCase {
    func testApplaunchArgumentsIncludeAppId() {
        let args = SteamGameLaunch.applaunchArguments(appId: "1245620")
        XCTAssertEqual(
            args,
            [
                "steam.exe",
                "-no-cef-sandbox",
                "-cef-disable-gpu",
                "-noverifyfiles",
                "-applaunch",
                "1245620"
            ]
        )
        XCTAssertTrue(args.contains("-applaunch"))
        XCTAssertEqual(args.last, "1245620")
    }

    func testApplaunchOmittedOnFirstRunUpdate() {
        XCTAssertEqual(
            SteamGameLaunch.applaunchArguments(appId: "1", firstRunUpdate: true),
            ["steam.exe"]
        )
    }

    func testRungameURI() {
        XCTAssertEqual(SteamGameLaunch.rungameURI(appId: "570"), "steam://rungameid/570")
    }

    func testNeedsRestartWhenEngineDiffers() {
        let needed = BottleRuntimeProfile(engine: .staging, graphics: .dxvk)
        XCTAssertTrue(
            SteamGameLaunch.needsClientRestart(
                isRunning: true,
                runningProfile: BottleRuntimeProfile(engine: .grappleWine, graphics: .dxmt),
                runningEngineFromProcess: .grappleWine,
                needed: needed
            )
        )
        XCTAssertFalse(
            SteamGameLaunch.needsClientRestart(
                isRunning: true,
                runningProfile: needed,
                runningEngineFromProcess: .staging,
                needed: needed
            )
        )
        XCTAssertFalse(
            SteamGameLaunch.needsClientRestart(
                isRunning: false,
                runningProfile: nil,
                runningEngineFromProcess: nil,
                needed: needed
            )
        )
    }

    func testNeedsRestartFromProcessEngineAlone() {
        let needed = BottleRuntimeProfile(engine: .staging, graphics: .dxvk)
        XCTAssertTrue(
            SteamGameLaunch.needsClientRestart(
                isRunning: true,
                runningProfile: nil,
                runningEngineFromProcess: .grappleWine,
                needed: needed
            )
        )
    }

    func testClientWineDebugNeverVerbose() {
        XCTAssertEqual(SteamGameLaunch.clientWineDebug(processEnvironment: [:]), "-all")
        // Host override still wins.
        XCTAssertEqual(
            SteamGameLaunch.clientWineDebug(processEnvironment: ["VERMUT_WINEDEBUG": "+seh"]),
            "+seh"
        )
    }

    func testDetectRunningEngineFromProcessLines() {
        let prefix = "/Users/me/Library/Application Support/Vermut/bottles/steam/prefix"
        let stagingRoot = "/Users/me/Library/Application Support/Vermut/engines/staging"
        let lines = [
            "12345 \(stagingRoot)/bin/wineserver -f",
            "12346 WINEPREFIX=\(prefix) \(stagingRoot)/bin/wine64 steam.exe"
        ]
        let engine = SteamGameLaunch.detectRunningEngine(
            prefixPath: prefix,
            processLines: lines,
            engineInstallPaths: [
                .grappleWine: "/Users/me/Library/Application Support/Vermut/engines/grapple-wine",
                .staging: stagingRoot,
                .devel: "/Users/me/Library/Application Support/Vermut/engines/devel"
            ]
        )
        XCTAssertEqual(engine, .staging)
    }

    func testStoreLaunchRecipeApplaunch() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        let recipe = StoreLaunchRecipe.build(
            store: .steam,
            executable: steam,
            wineLibDir: wineLib,
            steamAppId: "1245620"
        )
        XCTAssertEqual(recipe.arguments, SteamGameLaunch.applaunchArguments(appId: "1245620"))
        XCTAssertEqual(recipe.environment["WINEDEBUG"], "-all")
    }

    func testStoreLaunchRecipeWithoutAppIdUnchanged() {
        let wineLib = URL(fileURLWithPath: "/engines/grapple-wine/lib/wine")
        let steam = URL(fileURLWithPath: "/bottles/steam/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        let recipe = StoreLaunchRecipe.build(store: .steam, executable: steam, wineLibDir: wineLib)
        XCTAssertEqual(
            recipe.arguments,
            ["steam.exe", "-no-cef-sandbox", "-cef-disable-gpu", "-noverifyfiles"]
        )
        XCTAssertFalse(recipe.arguments.contains("-applaunch"))
    }

    func testRestartInfoMentionsEngine() {
        let message = SteamGameLaunch.restartInfoMessage(neededEngine: .staging)
        XCTAssertTrue(message.contains(WineEngine.staging.userFacingName))
        XCTAssertTrue(message.lowercased().contains("restart") || message.lowercased().contains("reopen"))
    }
}
