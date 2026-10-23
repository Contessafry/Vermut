import XCTest
@testable import CaskLauncherCore

final class LegendaryTests: XCTestCase {

    func testAuthorizationCodeFromJSONAndURL() {
        let json = #"{"redirectUrl":"https://localhost","authorizationCode":"abcDEF123","sid":null}"#
        XCTAssertEqual(LegendaryParse.authorizationCode(in: json), "abcDEF123")

        let wrapped = "Please copy this:\n\(json)\n"
        XCTAssertEqual(LegendaryParse.authorizationCode(in: wrapped), "abcDEF123")

        let url = URL(string: "https://www.epicgames.com/id/api/redirect?authorizationCode=xyz789&clientId=34a02cf8")!
        XCTAssertEqual(LegendaryParse.authorizationCode(from: url), "xyz789")
        XCTAssertEqual(
            LegendaryParse.authorizationCode(in: "https://legendary.gl/epiclogin?authorizationCode=fromQuery"),
            "fromQuery"
        )
        XCTAssertNil(LegendaryParse.authorizationCode(in: "no code here"))
    }

    func testOwnedListPrefersTallCoverAndSkipsDLC() throws {
        let json = """
        [
          {
            "app_name": "Fortnite",
            "app_title": "Fortnite",
            "metadata": {
              "keyImages": [
                {"type": "Thumbnail", "url": "https://cdn.example/thumb.jpg"},
                {"type": "DieselGameBoxTall", "url": "https://cdn.example/tall.jpg"},
                {"type": "DieselGameBox", "url": "https://cdn.example/wide.jpg"}
              ]
            }
          },
          {
            "app_name": "FortniteSeasonPass",
            "app_title": "Fortnite Season Pass",
            "metadata": { "mainGameItem": { "id": "Fortnite" } }
          }
        ]
        """.data(using: .utf8)!
        let games = LegendaryParse.parseOwned(data: json)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games[0].appName, "Fortnite")
        XCTAssertEqual(games[0].coverURLs.first?.absoluteString, "https://cdn.example/tall.jpg")
        XCTAssertEqual(games[0].coverURLs[1].absoluteString, "https://cdn.example/thumb.jpg")
        XCTAssertTrue(games[1].isDLC)
    }

    func testMergeMarksInstalledOwnedGames() {
        let owned = [
            LegendaryGame(appName: "Celeste", title: "Celeste", coverURLs: [URL(string: "https://cdn.example/c.jpg")!]),
            LegendaryGame(appName: "Hades", title: "Hades")
        ]
        let installed = [
            LegendaryGame(appName: "Celeste", title: "Celeste", isInstalled: true, installPath: "/Games/Celeste")
        ]
        let merged = LegendaryParse.merge(owned: owned, installed: installed)
        XCTAssertEqual(merged.map(\.appName), ["Celeste", "Hades"])
        XCTAssertTrue(merged[0].isInstalled)
        XCTAssertEqual(merged[0].installPath, "/Games/Celeste")
        XCTAssertEqual(merged[0].coverURLs.first?.absoluteString, "https://cdn.example/c.jpg")
        XCTAssertFalse(merged[1].isInstalled)
        let library = merged[0].asInstalledGame()
        XCTAssertEqual(library.store, .epic)
        XCTAssertEqual(library.appId, "Celeste")
        XCTAssertTrue(library.isInstalled)
    }

    func testInstalledJSONAndStatusAccount() {
        let installed = """
        [
          {"app_name": "Celeste", "title": "Celeste", "install_path": "/prefix/drive_c/Games/Celeste", "is_dlc": false}
        ]
        """.data(using: .utf8)!
        let games = LegendaryParse.parseInstalled(data: installed)
        XCTAssertEqual(games.first?.installPath, "/prefix/drive_c/Games/Celeste")
        XCTAssertTrue(games.first?.isInstalled == true)

        let status = #"{"account":"PlayerOne","games_available":12,"games_installed":1}"#.data(using: .utf8)!
        XCTAssertEqual(LegendaryParse.parseAccount(statusJSON: status)?.displayName, "PlayerOne")
        let empty = #"{"account":" "}"#.data(using: .utf8)!
        XCTAssertNil(LegendaryParse.parseAccount(statusJSON: empty))

        let user = #"{"displayName":"PlayerOne","accountId":"abc"}"#.data(using: .utf8)!
        XCTAssertEqual(LegendaryParse.parseUserJSON(user)?.displayName, "PlayerOne")
    }

    func testProgressParserReadsLegendaryDownloadLines() {
        XCTAssertEqual(LegendaryParse.progressFraction(in: "[DL] 12.50% (1.2/10 GiB)") ?? -1, 0.125, accuracy: 0.0001)
        XCTAssertEqual(LegendaryParse.progressFraction(in: "[DLManager] INFO: = Progress: 99.9%, ETA: 00:01") ?? -1, 0.999, accuracy: 0.0001)
        XCTAssertEqual(LegendaryParse.progressFraction(in: "Progress: 40%") ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertNil(LegendaryParse.progressFraction(in: "Getting game list..."))
    }

    func testCLIArgumentsUseWindowsPlatformAndWinePrefix() {
        XCTAssertEqual(LegendaryCLI.windowsPlatform, "Windows")
        XCTAssertEqual(
            LegendaryCLI.listOwnedArguments(),
            ["list", "--json", "--platform", "Windows"]
        )
        XCTAssertEqual(
            LegendaryCLI.listInstalledArguments(),
            ["list-installed", "--json", "--platform", "Windows"]
        )
        XCTAssertEqual(
            LegendaryCLI.installArguments(appName: "Celeste", basePath: "/prefix/drive_c/Games"),
            ["install", "Celeste", "--base-path", "/prefix/drive_c/Games", "-y", "--platform", "Windows"]
        )
        XCTAssertEqual(
            LegendaryCLI.launchArguments(appName: "Celeste", wine: "/opt/wine/bin/wine64", prefix: "/prefix"),
            ["launch", "Celeste", "--wine", "/opt/wine/bin/wine64", "--wine-prefix", "/prefix"]
        )
        XCTAssertEqual(
            LegendaryCLI.authCodeArguments("abc"),
            ["auth", "--code", "abc", "--disable-webview"]
        )
        XCTAssertEqual(LegendaryCLI.loginPageURL.absoluteString, "https://legendary.gl/epiclogin")
        XCTAssertTrue(LegendaryCLI.sourceURL.absoluteString.contains("derrod/legendary"))
    }

    func testVulkanDisabledLeftoversBecomeBuiltinForDXVK() {
        let userReg = """
        [Software\\\\Wine\\\\DllOverrides]
        "vulkan-1"="d"
        "winevulkan"="d"
        "d3d11"="native"
        """
        let ops = EpicVulkanPolicy.leftoverDisabledVulkanWrites(userReg: userReg, backend: .dxvk)
        let added = ops.compactMap(\.added)
        XCTAssertTrue(added.contains { $0.value == "vulkan-1" && $0.data == "builtin" })
        XCTAssertTrue(added.contains { $0.value == "winevulkan" && $0.data == "builtin" })
        XCTAssertEqual(EpicVulkanPolicy.dxvkOverrideString, "d3d9,d3d10core,d3d11,dxgi=n;vulkan-1,winevulkan=b")
    }

    func testEpicCardCopyFitsTwoLinesAndTracksAuth() {
        XCTAssertEqual(
            EpicStoreCopy.blurb,
            "Your Epic library, via Legendary. Windows games run in this bottle."
        )
        XCTAssertLessThanOrEqual(EpicStoreCopy.blurb.count, 80)
        XCTAssertFalse(EpicStoreCopy.blurb.contains("Windows titles run in this b"))
        XCTAssertEqual(EpicStoreCopy.badge(isLoggedIn: false, account: nil), "Signed out")
        XCTAssertEqual(EpicStoreCopy.badge(isLoggedIn: false, account: "Ada"), "Signed out")
        XCTAssertEqual(EpicStoreCopy.badge(isLoggedIn: true, account: "Ada"), "Signed in · Ada")
        XCTAssertEqual(EpicStoreCopy.signedInBadge(account: "Ada"), "Signed in · Ada")
        XCTAssertFalse(EpicStoreCopy.graphicsHelp.localizedCaseInsensitiveContains("grapple"))
        XCTAssertFalse(EpicStoreCopy.graphicsHelp.localizedCaseInsensitiveContains("casklauncher"))
        XCTAssertTrue(EpicStoreCopy.graphicsHelp.contains("Vermut Wine"))
    }

    func testLegendaryPathsLiveUnderEnginesAndEpicBottle() {
        let binary = PathManager.shared.legendaryBinaryURL
        XCTAssertTrue(binary.path.contains("/engines/legendary/legendary"))
        let config = PathManager.shared.legendaryConfigURL
        XCTAssertTrue(config.path.contains("/bottles/epic/legendary"))
        XCTAssertEqual(LegendaryManager.shared.processEnvironment()["LEGENDARY_CONFIG_PATH"], config.path)
    }
}
