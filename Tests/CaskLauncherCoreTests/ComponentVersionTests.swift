import XCTest
@testable import CaskLauncherCore

final class ComponentVersionTests: XCTestCase {
    func testNormalizeStripsLeadingV() {
        XCTAssertEqual(ComponentVersion.normalize("v0.80"), "0.80")
        XCTAssertEqual(ComponentVersion.normalize("V1.2.3"), "1.2.3")
        XCTAssertEqual(ComponentVersion.normalize(" 11.18 "), "11.18")
    }

    func testCanonicalTagPrefersVPrefixForNumeric() {
        XCTAssertEqual(ComponentVersion.canonicalTag("v0.80"), "v0.80")
        XCTAssertEqual(ComponentVersion.canonicalTag("0.80"), "v0.80")
        XCTAssertEqual(ComponentVersion.canonicalTag("v0.70"), "v0.70")
    }

    func testCompareOrdersSemanticVersions() {
        XCTAssertEqual(ComponentVersion.compare("v0.70", "v0.80"), .orderedAscending)
        XCTAssertEqual(ComponentVersion.compare("v0.80", "0.80"), .orderedSame)
        XCTAssertEqual(ComponentVersion.compare("v1.0", "v0.90"), .orderedDescending)
        XCTAssertEqual(ComponentVersion.compare("11.18", "11.17"), .orderedDescending)
    }

    func testIsAtLeast() {
        XCTAssertTrue(ComponentVersion.isAtLeast("v0.80", minimum: "v0.80"))
        XCTAssertTrue(ComponentVersion.isAtLeast("v0.90", minimum: "0.80"))
        XCTAssertFalse(ComponentVersion.isAtLeast("v0.70", minimum: "v0.80"))
    }
}
