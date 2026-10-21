import XCTest
@testable import CaskLauncherCore

final class SemVerTests: XCTestCase {
    func testParseStripsVAndBuildMetadata() {
        let v = SemVer.parse("v1.2.0-beta.1+build.5")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 0)
        XCTAssertEqual(v?.prereleaseIdentifiers, ["beta", "1"])
        XCTAssertTrue(v?.isPrerelease == true)
    }

    func testStableGreaterThanMatchingPrerelease() {
        XCTAssertEqual(SemVer.compare("1.2.0", "1.2.0-beta.2"), .orderedDescending)
        XCTAssertEqual(SemVer.compare("1.2.0-beta.2", "1.2.0"), .orderedAscending)
    }

    func testPrereleaseOrdering() {
        // 1.2.0 > 1.2.0-beta.2 > 1.2.0-beta.1
        XCTAssertEqual(SemVer.compare("1.2.0-beta.2", "1.2.0-beta.1"), .orderedDescending)
        XCTAssertEqual(SemVer.compare("1.2.0-beta.1", "1.2.0-beta.2"), .orderedAscending)
        XCTAssertEqual(SemVer.compare("v1.2.0", "1.2.0-beta.2"), .orderedDescending)
    }

    func testNumericCoreOrdering() {
        XCTAssertEqual(SemVer.compare("1.2.0", "1.1.9"), .orderedDescending)
        XCTAssertEqual(SemVer.compare("2.0.0-beta.1", "1.9.9"), .orderedDescending)
    }

    func testTagIsPrerelease() {
        XCTAssertTrue(SemVer.tagIsPrerelease("v1.2.0-beta.1"))
        XCTAssertTrue(SemVer.tagIsPrerelease("1.0.0-rc.1"))
        XCTAssertFalse(SemVer.tagIsPrerelease("1.2.0"))
        XCTAssertFalse(SemVer.tagIsPrerelease("v1.1.3"))
    }

    func testSelectCandidateStableIgnoresPrerelease() {
        let releases = [
            ReleaseInfo(tagName: "v1.2.0-beta.1", htmlUrl: "https://example/beta", prerelease: true),
            ReleaseInfo(tagName: "v1.1.3", htmlUrl: "https://example/stable", prerelease: false)
        ]
        let candidate = UpdateChecker.selectCandidate(
            from: releases,
            channel: .stable,
            currentVersion: "1.1.0"
        )
        XCTAssertEqual(candidate?.tagName, "v1.1.3")
    }

    func testSelectCandidateBetaPicksHighestIncludingPrerelease() {
        let releases = [
            ReleaseInfo(tagName: "v1.1.3", htmlUrl: "https://example/stable", prerelease: false),
            ReleaseInfo(tagName: "v1.2.0-beta.1", htmlUrl: "https://example/b1", prerelease: true),
            ReleaseInfo(tagName: "v1.2.0-beta.2", htmlUrl: "https://example/b2", prerelease: true)
        ]
        let candidate = UpdateChecker.selectCandidate(
            from: releases,
            channel: .beta,
            currentVersion: "1.1.3"
        )
        XCTAssertEqual(candidate?.tagName, "v1.2.0-beta.2")
    }

    func testStableNeverSuggestsDowngradeFromBetaInstall() {
        // Installed 1.2.0-beta.1; latest stable is 1.1.3 → no offer.
        let releases = [
            ReleaseInfo(tagName: "v1.1.3", htmlUrl: "https://example/stable", prerelease: false),
            ReleaseInfo(tagName: "v1.2.0-beta.1", htmlUrl: "https://example/beta", prerelease: true)
        ]
        let candidate = UpdateChecker.selectCandidate(
            from: releases,
            channel: .stable,
            currentVersion: "1.2.0-beta.1"
        )
        XCTAssertNil(candidate)
    }

    func testStableOffersMatchingStableOverInstalledBeta() {
        // Installed 1.2.0-beta.1; stable 1.2.0 ships → offer upgrade to stable.
        let releases = [
            ReleaseInfo(tagName: "v1.2.0", htmlUrl: "https://example/stable", prerelease: false)
        ]
        let candidate = UpdateChecker.selectCandidate(
            from: releases,
            channel: .stable,
            currentVersion: "1.2.0-beta.1"
        )
        XCTAssertEqual(candidate?.tagName, "v1.2.0")
    }

    func testDraftReleasesAreIgnored() {
        let releases = [
            ReleaseInfo(tagName: "v9.9.9", htmlUrl: "https://example/draft", prerelease: false, draft: true),
            ReleaseInfo(tagName: "v1.1.4", htmlUrl: "https://example/ok", prerelease: false)
        ]
        let candidate = UpdateChecker.selectCandidate(
            from: releases,
            channel: .stable,
            currentVersion: "1.1.3"
        )
        XCTAssertEqual(candidate?.tagName, "v1.1.4")
    }

    func testUpdateChannelDefaultIsStable() {
        XCTAssertEqual(UpdateChannel.resolved(from: nil), .stable)
        XCTAssertEqual(UpdateChannel.resolved(from: "nope"), .stable)
        XCTAssertEqual(AppConfiguration().resolvedUpdateChannel, .stable)
    }
}
