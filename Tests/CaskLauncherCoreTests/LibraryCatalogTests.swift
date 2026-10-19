import XCTest
@testable import CaskLauncherCore

final class LibraryCatalogTests: XCTestCase {

    func testACFParserReadsNameAndAppIdFromTabSeparatedLines() {
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"2578500"
        \t"Universe"\t\t"1"
        \t"name"\t\t"Mewgenics"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Mewgenics"
        \t"UserConfig"
        \t{
        \t\t"name"\t\t"english"
        \t}
        }
        """
        let values = ValveKeyValues.firstStringValues(in: acf)
        XCTAssertEqual(values["appid"], "2578500")
        XCTAssertEqual(values["name"], "Mewgenics")
        XCTAssertEqual(values["installdir"], "Mewgenics")

        let game = StoreLibrary.shared.parseSteamACF(content: acf)
        XCTAssertEqual(game?.appId, "2578500")
        XCTAssertEqual(game?.name, "Mewgenics")
        XCTAssertEqual(game?.store, .steam)
        XCTAssertEqual(game?.coverURLs.first?.absoluteString, "https://steamcdn-a.akamaihd.net/steam/apps/2578500/library_600x900.jpg")
        XCTAssertEqual(game?.coverURLs.last?.absoluteString, "https://steamcdn-a.akamaihd.net/steam/apps/2578500/header.jpg")
    }

    func testACFParserDoesNotTreatTabsAsTheTitle() {
        // Regression: splitting on quotes left `\t\t` as parts[1], so the library
        // card rendered a blank name and a useless cover URL.
        let line = "\t\"name\"\t\t\"Mewgenics\""
        let values = ValveKeyValues.firstStringValues(in: line)
        XCTAssertEqual(values["name"], "Mewgenics")
        XCTAssertNotEqual(values["name"], "\t\t")
        XCTAssertNotEqual(values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), "")

        let tokens = ValveKeyValues.tokenize(line)
        XCTAssertEqual(tokens, [.string("name"), .string("Mewgenics")])
    }

    func testVDFTokenizerReadsTabSeparatedPairsAndNestedTables() {
        let raw = Data("\t\"appid\"\t\t\"2578500\"\n\t\"name\"\t\t\"Mewgenics\"\n".utf8)
        let content = String(data: raw, encoding: .utf8)!
        let values = ValveKeyValues.firstStringValues(in: content)
        XCTAssertEqual(values["appid"], "2578500")
        XCTAssertEqual(values["name"], "Mewgenics")
        XCTAssertFalse(values.values.contains("\t\t"))
        XCTAssertFalse(values.keys.contains("\t\t"))
    }

    func testVDFTokenizerReadsEveryLibraryFolderPath() {
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
        \t\t"label"\t\t""
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"D:\\\\SteamLibrary"
        \t}
        }
        """
        XCTAssertEqual(
            ValveKeyValues.allStringValues(forKey: "path", in: vdf),
            [
                #"C:\Program Files (x86)\Steam"#,
                #"D:\SteamLibrary"#
            ]
        )
    }

    func testSteamHelperListInstalledGamesParsesACFOnDisk() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-acf-\(UUID().uuidString)", isDirectory: true)
        let steamapps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"2578500"
        \t"name"\t\t"Mewgenics"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Mewgenics"
        }
        """
        try acf.write(
            to: steamapps.appendingPathComponent("appmanifest_2578500.acf"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: prefix) }

        let games = try SteamHelper.shared.listInstalledGames(in: prefix)
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.name, "Mewgenics")
        XCTAssertNotEqual(games.first?.name, "\t\t")
        XCTAssertEqual(games.first?.appId, "2578500")
        XCTAssertNotEqual(games.first?.appId, "\t\t")
    }

    func testSteamHelperReadsExtraLibraryFromTabSeparatedVDF() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-vdf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let steamapps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        let extraRoot = prefix.appendingPathComponent("drive_d/SteamLibrary")
        let extraApps = extraRoot.appendingPathComponent("steamapps")
        try FileManager.default.createDirectory(at: extraApps, withIntermediateDirectories: true)
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"D:\\\\SteamLibrary"
        \t}
        }
        """
        try vdf.write(to: steamapps.appendingPathComponent("libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"400"
        \t"name"\t\t"Portal"
        \t"StateFlags"\t\t"4"
        }
        """
        try acf.write(to: extraApps.appendingPathComponent("appmanifest_400.acf"), atomically: true, encoding: .utf8)

        let games = try SteamHelper.shared.listInstalledGames(in: prefix)
        XCTAssertEqual(games.map(\.name), ["Portal"])
        XCTAssertEqual(games.first?.appId, "400")
    }

    func testSkipsSteamworksRedistributable() {
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"228980"
        \t"name"\t\t"Steamworks Common Redistributables"
        \t"StateFlags"\t\t"4"
        }
        """
        XCTAssertNil(StoreLibrary.shared.parseSteamACF(content: acf))
    }

    func testSkipsNotFullyInstalled() {
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"1"
        \t"name"\t\t"Downloading"
        \t"StateFlags"\t\t"2"
        }
        """
        XCTAssertNil(StoreLibrary.shared.parseSteamACF(content: acf))
    }

    func testEpicItemParsesDisplayName() throws {
        let json = """
        {
          "FormatVersion": 0,
          "bIsIncompleteInstall": false,
          "AppName": "Fortnite",
          "DisplayName": "Fortnite",
          "InstallLocation": "C:\\\\Program Files\\\\Epic Games\\\\Fortnite"
        }
        """.data(using: .utf8)!
        let game = StoreLibrary.shared.parseEpicItem(data: json)
        XCTAssertEqual(game?.name, "Fortnite")
        XCTAssertEqual(game?.appId, "Fortnite")
        XCTAssertEqual(game?.store, .epic)
    }

    func testGOGInfoParsesNameAndGameId() {
        let json = """
        { "gameId": "1207664663", "name": "The Witcher 3: Wild Hunt" }
        """.data(using: .utf8)!
        let game = StoreLibrary.shared.parseGOGInfo(data: json)
        XCTAssertEqual(game?.name, "The Witcher 3: Wild Hunt")
        XCTAssertEqual(game?.appId, "1207664663")
        XCTAssertEqual(game?.store, .gog)
    }

    func testCoverCacheAcceptsJPEGAndRejectsHTML() {
        XCTAssertTrue(CoverCache.isImageData(Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 32))))
        XCTAssertTrue(CoverCache.isImageData(Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 32))))
        let html = Data("<html>404</html>".utf8)
        XCTAssertFalse(CoverCache.isImageData(html))
    }

    func testCoverCacheReadsLocalFileAndStoresIt() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-cover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("cover.jpg")
        var jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        jpeg.append(contentsOf: [UInt8](repeating: 0x11, count: 64))
        try jpeg.write(to: source)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cacheFile = CoverCache.fileURL(store: .steam, appId: "test-cover-cache")
        defer { try? FileManager.default.removeItem(at: cacheFile) }
        let loaded = await CoverCache.load(urls: [source], store: .steam, appId: "test-cover-cache")
        XCTAssertEqual(loaded?.prefix(3), jpeg.prefix(3))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }
}
