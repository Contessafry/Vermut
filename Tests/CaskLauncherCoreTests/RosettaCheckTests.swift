import XCTest
@testable import CaskLauncherCore

private struct StubRosettaRunner: RosettaCommandRunning {
    let result: Bool
    func probeX86Translation() -> Bool { result }
}

final class RosettaCheckTests: XCTestCase {
    func testIntelNeverRequiresRosetta() {
        XCTAssertEqual(
            RosettaCheck.decide(isAppleSilicon: false, probeSucceeded: false),
            .notRequired
        )
        XCTAssertEqual(
            RosettaCheck.decide(isAppleSilicon: false, probeSucceeded: true),
            .notRequired
        )
        XCTAssertFalse(RosettaCheck.decide(isAppleSilicon: false, probeSucceeded: false).shouldShowInstallBanner)
        XCTAssertTrue(RosettaCheck.decide(isAppleSilicon: false, probeSucceeded: false).isUsable)
    }

    func testAppleSiliconMissingShowsBanner() {
        let decision = RosettaCheck.decide(isAppleSilicon: true, probeSucceeded: false)
        XCTAssertEqual(decision, .missing)
        XCTAssertTrue(decision.shouldShowInstallBanner)
        XCTAssertFalse(decision.isUsable)
    }

    func testAppleSiliconPresentHidesBanner() {
        let decision = RosettaCheck.decide(isAppleSilicon: true, probeSucceeded: true)
        XCTAssertEqual(decision, .present)
        XCTAssertFalse(decision.shouldShowInstallBanner)
        XCTAssertTrue(decision.isUsable)
    }

    func testEvaluateUsesInjectableRunner() {
        XCTAssertEqual(
            RosettaCheck.evaluate(isAppleSilicon: true, runner: StubRosettaRunner(result: false)),
            .missing
        )
        XCTAssertEqual(
            RosettaCheck.evaluate(isAppleSilicon: true, runner: StubRosettaRunner(result: true)),
            .present
        )
        XCTAssertEqual(
            RosettaCheck.evaluate(isAppleSilicon: false, runner: StubRosettaRunner(result: false)),
            .notRequired
        )
    }
}
