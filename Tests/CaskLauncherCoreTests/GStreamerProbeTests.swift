import XCTest
@testable import CaskLauncherCore

final class GStreamerProbeTests: XCTestCase {
    func testCandidatePathsIncludeSystemFramework() {
        XCTAssertTrue(GStreamerProbe.candidatePaths.contains("/Library/Frameworks/GStreamer.framework"))
        XCTAssertFalse(GStreamerProbe.missingMessage.isEmpty)
        XCTAssertTrue(GStreamerProbe.installHint.contains("gstreamer"))
    }

    func testProbeReturnsConsistentStatus() {
        let status = GStreamerProbe.probe()
        if status.isPresent {
            XCTAssertNotNil(status.frameworkURL)
            XCTAssertNil(status.userFacingMessage)
        } else {
            XCTAssertNotNil(status.userFacingMessage)
        }
    }

    func testWineEngineGStreamerRequirement() {
        XCTAssertFalse(WineEngine.grappleWine.requiresGStreamer)
        XCTAssertTrue(WineEngine.staging.requiresGStreamer)
        XCTAssertTrue(WineEngine.devel.requiresGStreamer)
    }

    func testPickerStatusLabelForMissingEngine() {
        // pickerStatusLabel is nonisolated; keep this test off @MainActor so Linux `swift test` can discover it.
        let label = WineEnginesViewModel.pickerStatusLabel(for: .staging)
        XCTAssertFalse(label.isEmpty)
    }
}
