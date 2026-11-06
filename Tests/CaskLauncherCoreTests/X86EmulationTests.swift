import XCTest
@testable import CaskLauncherCore

final class X86EmulationTests: XCTestCase {
    func testRosettaIsDefault() {
        XCTAssertEqual(AppConfiguration().resolvedX86Emulation, .rosetta)
        XCTAssertEqual(X86EmulationMode.resolved(from: "nope"), .rosetta)
        XCTAssertEqual(X86EmulationMode.fex.userFacingName, "FEX")
    }

    func testDecodeMissingX86EmulationDefaultsToRosetta() throws {
        let json = Data(#"{}"#.utf8)
        let config = try JSONDecoder().decode(AppConfiguration.self, from: json)
        XCTAssertEqual(config.resolvedX86Emulation, .rosetta)
    }

    func testFEXEnvironmentOnlyWhenRuntimeIsComplete() {
        let missing = FEXProbeResult(fexLibrariesFound: false, wineArchitecture: .x86_64)
        XCTAssertFalse(missing.canRunFEX)
        XCTAssertTrue(FEXRuntime.environment(probe: missing).isEmpty)

        let ready = FEXProbeResult(
            fexLibrariesFound: true,
            fexRoot: URL(fileURLWithPath: "/opt/fex-emu"),
            wineArchitecture: .arm64
        )
        XCTAssertTrue(ready.canRunFEX)
        XCTAssertEqual(FEXRuntime.environment(probe: ready)["FEX_ROOTFS"], "/opt/fex-emu")
    }

    func testApplyKeepsRosettaHintWhenFEXCannotRun() {
        var env: [String: String] = [:]
        X86Emulation.apply(
            to: &env,
            mode: .fex,
            probe: FEXProbeResult(fexLibrariesFound: false, wineArchitecture: .x86_64),
            store: .steam
        )
        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertNil(env["FEX_ROOTFS"])
    }

    func testApplyDropsRosettaHintWhenFEXRuns() {
        var env: [String: String] = ["ROSETTA_ADVERTISE_AVX": "1"]
        X86Emulation.apply(
            to: &env,
            mode: .fex,
            probe: FEXProbeResult(
                fexLibrariesFound: true,
                fexRoot: URL(fileURLWithPath: "/tmp/fex"),
                wineArchitecture: .arm64
            ),
            store: .steam
        )
        XCTAssertNil(env["ROSETTA_ADVERTISE_AVX"])
        XCTAssertEqual(env["FEX_ROOTFS"], "/tmp/fex")
    }

    func testWineArchitectureReadsMachOCPUType() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-macho-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        var x64 = Data([0xcf, 0xfa, 0xed, 0xfe])
        var cpu64 = UInt32(0x0100_0007)
        x64.append(Data(bytes: &cpu64, count: 4))
        try x64.write(to: url)
        XCTAssertEqual(FEXRuntime.wineArchitecture(at: url), .x86_64)

        var arm = Data([0xcf, 0xfa, 0xed, 0xfe])
        var cpuArm = UInt32(0x0100_000c)
        arm.append(Data(bytes: &cpuArm, count: 4))
        try arm.write(to: url)
        XCTAssertEqual(FEXRuntime.wineArchitecture(at: url), .arm64)
    }

    func testContainsFEXMarkers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-fex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(FEXRuntime.containsFEXMarkers(root))
        try Data("x".utf8).write(to: root.appendingPathComponent("libFEXCore.dylib"))
        XCTAssertTrue(FEXRuntime.containsFEXMarkers(root))
    }
}
