import XCTest
@testable import CaskLauncherCore

final class D3DMetalDetectorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("d3dmetal-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testMinimumVersionIs2() {
        XCTAssertEqual(D3DMetalDetector.minimumVersion, "2.0")
        XCTAssertTrue(ComponentVersion.isAtLeast("2.0", minimum: "2.0"))
        XCTAssertTrue(ComponentVersion.isAtLeast("3.0", minimum: "2.0"))
        XCTAssertFalse(ComponentVersion.isAtLeast("1.1", minimum: "2.0"))
    }

    func testCandidateRootsExcludeCrossOver() {
        let roots = D3DMetalDetector.candidateRoots(appSupport: tempRoot)
        XCTAssertTrue(roots.contains(where: { $0.path.hasSuffix("/D3DMetal") }))
        XCTAssertFalse(roots.contains(where: { $0.path.localizedCaseInsensitiveContains("CrossOver") }))
    }

    func testValidateMissingFrameworkIsInvalid() throws {
        let empty = tempRoot.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let presence = D3DMetalDetector.validate(root: empty)
        guard case .invalid(let reason) = presence else {
            return XCTFail("Expected invalid, got \(presence)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("D3DMetal.framework"))
    }

    func testValidateFoundWithFrameworkAndVersion() throws {
        let lib = tempRoot.appendingPathComponent("redist/lib", isDirectory: true)
        let framework = lib.appendingPathComponent("external/D3DMetal.framework/Versions/Current/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "3.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: framework.appendingPathComponent("Info.plist"))

        let presence = D3DMetalDetector.validate(root: lib)
        guard case .found(let version, let root) = presence else {
            return XCTFail("Expected found, got \(presence)")
        }
        XCTAssertEqual(version, "3.0")
        XCTAssertTrue(root.path.contains("redist/lib"))
    }

    func testValidateUnsupportedOldVersion() throws {
        let lib = tempRoot.appendingPathComponent("old/lib", isDirectory: true)
        let framework = lib.appendingPathComponent("external/D3DMetal.framework/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "1.1"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: framework.appendingPathComponent("Info.plist"))

        let presence = D3DMetalDetector.validate(root: lib)
        guard case .unsupported(let version, _) = presence else {
            return XCTFail("Expected unsupported, got \(presence)")
        }
        XCTAssertEqual(version, "1.1")
        XCTAssertFalse(presence.isUsable)
    }

    func testDetectRespectsCustomPath() throws {
        let lib = tempRoot.appendingPathComponent("custom-lib", isDirectory: true)
        let framework = lib.appendingPathComponent("D3DMetal.framework/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "2.1"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: framework.appendingPathComponent("Info.plist"))

        let result = D3DMetalDetector.detect(
            customPath: lib.path,
            isAppleSilicon: true
        )
        XCTAssertTrue(result.presence.isUsable)
        XCTAssertEqual(result.presence.versionString, "2.1")
    }

    func testDetectIntelHostIsUnavailable() {
        let result = D3DMetalDetector.detect(isAppleSilicon: false)
        guard case .unavailableOnIntel = result.presence else {
            return XCTFail("Expected unavailableOnIntel")
        }
    }

    func testInstallGuideHasFourSteps() {
        XCTAssertEqual(D3DMetalDetector.installGuideSteps.count, 4)
    }
}
