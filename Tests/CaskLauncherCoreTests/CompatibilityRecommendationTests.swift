import XCTest
@testable import CaskLauncherCore

final class CompatibilityRecommendationTests: XCTestCase {
    func testBrokenOnlyReportsDoNotRecommendABackend() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "1245620",
            gameName: "ELDEN RING",
            byGraphics: [
                "dxmt": .init(perfect: 0, issues: 0, broken: 3)
            ],
            recommended: "dxmt",
            totalReports: 3,
            knownNotWorking: [
                KnownNotWorkingCombo(graphics: "dxmt", engine: "vermut-wine")
            ]
        )
        XCTAssertNil(compat.effectiveRecommended)
        XCTAssertEqual(compat.effectiveKnownNotWorking.count, 1)
        XCTAssertEqual(compat.effectiveKnownNotWorking.first?.displayLabel, "DXMT (Vermut Wine)")
    }

    func testRecommendationRequiresWorkingReports() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "620",
            gameName: "Portal 2",
            byGraphics: [
                "dxmt": .init(perfect: 0, issues: 0, broken: 4),
                "dxvk": .init(perfect: 2, issues: 1, broken: 0)
            ],
            recommended: "dxvk",
            totalReports: 7
        )
        XCTAssertEqual(compat.effectiveRecommended, "dxvk")
    }

    func testLegacyJSONWithoutKnownNotWorkingFallsBack() {
        let json = """
        {
          "store": "steam",
          "gameId": "1",
          "gameName": "Kingsway",
          "byGraphics": { "dxmt": { "perfect": 0, "issues": 0, "broken": 2 } },
          "recommended": "dxmt",
          "totalReports": 2
        }
        """.data(using: .utf8)!
        let compat = try! JSONDecoder().decode(GameCompatibility.self, from: json)
        XCTAssertNil(compat.effectiveRecommended)
        XCTAssertEqual(compat.effectiveKnownNotWorking.map(\.graphics), ["dxmt"])
        XCTAssertTrue(compat.knownNotWorking.isEmpty)
    }

    func testDecodeKnownNotWorkingFromWorkflowJSON() throws {
        let json = """
        {
          "store": "steam",
          "gameId": "1",
          "byGraphics": { "dxvk": { "perfect": 0, "issues": 0, "broken": 1 } },
          "recommended": null,
          "knownNotWorking": [{ "graphics": "dxvk", "engine": "staging" }],
          "totalReports": 1
        }
        """.data(using: .utf8)!
        let compat = try JSONDecoder().decode(GameCompatibility.self, from: json)
        XCTAssertNil(compat.recommended)
        XCTAssertEqual(compat.knownNotWorking.first?.engine, "staging")
    }
}
