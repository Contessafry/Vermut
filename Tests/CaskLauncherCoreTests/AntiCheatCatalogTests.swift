import XCTest
@testable import CaskLauncherCore

final class AntiCheatCatalogTests: XCTestCase {
    private let catalog = AntiCheatCatalogFile(
        source: "AreWeAntiCheatYet/AreWeAntiCheatYet",
        sourceUrl: "https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet",
        homepage: "https://areweanticheatyet.com/",
        generated: "2026-10-26",
        note: "test",
        games: [
            AntiCheatEntry(
                steamId: "1245620",
                epicId: nil,
                name: "ELDEN RING",
                anticheats: ["Easy Anti-Cheat"],
                linuxStatus: "Denied",
                slug: "elden-ring"
            ),
            AntiCheatEntry(
                steamId: "578080",
                epicId: nil,
                name: "PUBG: Battlegrounds",
                anticheats: ["BattlEye"],
                linuxStatus: "Broken",
                slug: "pubg"
            )
        ]
    )

    func testLookupBySteamId() {
        let entry = AntiCheatCatalog.lookup(
            store: .steam,
            appId: "1245620",
            name: "Something Else",
            catalog: catalog
        )
        XCTAssertEqual(entry?.name, "ELDEN RING")
        XCTAssertTrue(entry?.usesEasyAntiCheat == true)
        XCTAssertTrue(entry?.libraryWarning.contains("Easy Anti-Cheat") == true)
    }

    func testLookupByNormalizedName() {
        let entry = AntiCheatCatalog.lookup(
            store: .gog,
            appId: "",
            name: "pubg battlegrounds",
            catalog: catalog
        )
        XCTAssertEqual(entry?.steamId, "578080")
        XCTAssertTrue(entry?.usesBattlEye == true)
    }

    func testUnknownGameHasNoWarning() {
        XCTAssertNil(
            AntiCheatCatalog.lookup(
                store: .steam,
                appId: "620",
                name: "Portal 2",
                catalog: catalog
            )
        )
    }

    func testBundledCatalogParsesAndIncludesEldenRing() {
        let file = AntiCheatCatalog.loadBundled()
        XCTAssertTrue(file.source.contains("AreWeAntiCheatYet"))
        if file.games.isEmpty {
            // Linux/SwiftPM may not copy the resource next to the test host.
            // Parsing the on-disk source file still validates the extract.
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/CaskLauncherCore/kernel-anticheat.json")
            guard let data = try? Data(contentsOf: url) else {
                return XCTFail("kernel-anticheat.json missing at \(url.path)")
            }
            let decoded = try? JSONDecoder().decode(AntiCheatCatalogFile.self, from: data)
            XCTAssertNotNil(decoded)
            XCTAssertTrue(decoded?.games.contains { $0.steamId == "1245620" } == true)
            return
        }
        XCTAssertTrue(file.games.contains { $0.steamId == "1245620" })
        XCTAssertTrue(file.games.contains { $0.usesBattlEye })
    }

    func testNormalizeNameStripsPunctuation() {
        XCTAssertEqual(
            AntiCheatCatalog.normalizeName("Tom Clancy's Rainbow Six® Siege"),
            AntiCheatCatalog.normalizeName("tom clancys rainbow six siege")
        )
    }
}
