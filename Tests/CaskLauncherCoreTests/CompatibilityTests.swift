import XCTest
@testable import CaskLauncherCore

final class CompatibilityTests: XCTestCase {
    func testCompatibilityReportCreation() {
        let report = CompatibilityReport(
            store: "steam",
            gameId: "123456",
            gameName: "Test Game",
            vermutVersion: "1.0.0",
            engine: "grapple-wine",
            graphics: "dxmt",
            macOS: "14.5",
            chip: "M2",
            playMinutes: 45,
            result: "perfect",
            autoDetectedCrash: false,
            note: "Works great"
        )
        
        XCTAssertEqual(report.store, "steam")
        XCTAssertEqual(report.gameId, "123456")
        XCTAssertEqual(report.result, "perfect")
    }
    
    func testGitHubURLGeneration() {
        let report = CompatibilityReport(
            store: "steam",
            gameId: "123456",
            gameName: "Portal 2",
            vermutVersion: "1.0.0",
            engine: "grapple-wine",
            graphics: "dxmt",
            macOS: "14.5",
            chip: "M2 Pro",
            playMinutes: 30,
            result: "perfect"
        )
        
        let url = CompatibilityService.shared.generateGitHubIssueURL(report: report)
        
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("github.com/Contessafry/Vermut/issues/new") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("template=compatibility-report.yml") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("Portal") ?? false)
    }
    
    func testGameCompatibilityResults() {
        let compat = GameCompatibility(
            store: "steam",
            gameId: "123",
            gameName: "Test",
            byGraphics: [
                "dxmt": GameCompatibility.GraphicsResults(perfect: 10, issues: 2, broken: 0),
                "dxvk": GameCompatibility.GraphicsResults(perfect: 3, issues: 1, broken: 1)
            ],
            recommended: "dxmt",
            totalReports: 17
        )
        
        XCTAssertEqual(compat.workingReports, 13)
        XCTAssertEqual(compat.issuesReports, 3)
        XCTAssertEqual(compat.brokenReports, 1)
        XCTAssertEqual(compat.totalReports, 17)
    }
    
    func testGameSessionTracking() {
        let tracker = GameSessionTracker.shared
        tracker.clearAllSessions()
        
        tracker.startSession(
            store: .steam,
            gameId: "123",
            gameName: "Test Game",
            engine: "grapple-wine",
            graphics: "dxmt"
        )
        
        let session = tracker.getSession(store: .steam, gameId: "123")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.gameId, "123")
        XCTAssertEqual(session?.gameName, "Test Game")
        
        let ended = tracker.endSession(store: .steam, gameId: "123")
        XCTAssertNotNil(ended)
        
        let gone = tracker.getSession(store: .steam, gameId: "123")
        XCTAssertNil(gone)
    }
    
    func testCompatibilityResultDisplayNames() {
        XCTAssertEqual(CompatibilityResult.perfect.displayName, "Works perfectly")
        XCTAssertEqual(CompatibilityResult.issues.displayName, "Minor issues")
        XCTAssertEqual(CompatibilityResult.broken.displayName, "Doesn't work")
    }
}
