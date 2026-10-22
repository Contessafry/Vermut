import XCTest
@testable import CaskLauncherCore

final class BottleNameValidatorTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(BottleNameValidator.validate("  ", existingNames: []), .empty)
        XCTAssertEqual(BottleNameValidator.errorMessage(for: .empty), "Enter a name.")
    }

    func testTooLong() {
        let name = String(repeating: "a", count: 41)
        XCTAssertEqual(BottleNameValidator.validate(name, existingNames: []), .tooLong)
        XCTAssertEqual(
            BottleNameValidator.errorMessage(for: .tooLong),
            "Use 40 characters or fewer."
        )
    }

    func testInvalidCharacters() {
        XCTAssertEqual(BottleNameValidator.validate("Foo/Bar", existingNames: []), .invalidCharacters)
        XCTAssertEqual(BottleNameValidator.validate("a:b", existingNames: []), .invalidCharacters)
        XCTAssertEqual(
            BottleNameValidator.errorMessage(for: .invalidCharacters),
            "Names can’t contain / : \\ * ? \" < > |."
        )
    }

    func testDuplicateIncludingStores() {
        XCTAssertEqual(
            BottleNameValidator.validate("Steam", existingNames: []),
            .duplicate(existingName: "Steam")
        )
        XCTAssertEqual(
            BottleNameValidator.validate("steam", existingNames: []),
            .duplicate(existingName: "Steam")
        )
        XCTAssertEqual(
            BottleNameValidator.validate("Retro", existingNames: ["retro", "Other"]),
            .duplicate(existingName: "retro")
        )
        let message = BottleNameValidator.errorMessage(for: .duplicate(existingName: "Steam"))
        XCTAssertEqual(message, "A bottle named “Steam” already exists.")
    }

    func testValidName() {
        XCTAssertNil(BottleNameValidator.validate("Retro Tools", existingNames: ["Steam"]))
    }

    func testSuggestedNameSkipsCollisions() {
        XCTAssertEqual(BottleNameValidator.suggestedName(existingNames: []), "New Bottle")
        XCTAssertEqual(
            BottleNameValidator.suggestedName(existingNames: ["New Bottle"]),
            "New Bottle 2"
        )
        XCTAssertEqual(
            BottleNameValidator.suggestedName(existingNames: ["New Bottle", "New Bottle 2"]),
            "New Bottle 3"
        )
    }
}

final class CustomBottleStoreTests: XCTestCase {
    func testAtomicRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-custom-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = CustomBottleStore()
        let bottle = CustomBottle(
            name: "Retro Tools",
            configuration: BottleConfiguration(windowsVersion: "win10"),
            programs: [
                BottleProgram(
                    displayName: "Builder",
                    windowsPath: #"C:\Program Files\UDB\Builder.exe"#,
                    kind: .launched,
                    lastRunAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ]
        )
        try store.save([bottle], appSupport: dir)
        store.invalidateCache()
        let loaded = try store.load(appSupport: dir)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Retro Tools")
        XCTAssertEqual(loaded[0].programs.count, 1)
        XCTAssertEqual(loaded[0].programs[0].kind, .launched)

        try store.remove(id: bottle.id, appSupport: dir)
        store.invalidateCache()
        XCTAssertTrue(try store.load(appSupport: dir).isEmpty)
    }
}

final class BottleSizeCacheTests: XCTestCase {
    func testCacheReturnsSameValueWithinTTL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.bin")
        try Data(repeating: 1, count: 1024).write(to: file)

        let cache = BottleSizeCache()
        cache.timeToLive = 60
        let first = cache.size(of: dir)
        XCTAssertEqual(first, 1024)

        try Data(repeating: 2, count: 2048).write(to: dir.appendingPathComponent("b.bin"))
        let cached = cache.size(of: dir)
        XCTAssertEqual(cached, 1024, "TTL cache should not recompute yet")

        let forced = cache.size(of: dir, force: true)
        XCTAssertEqual(forced, 1024 + 2048)
    }
}

final class ShortcutScannerTests: XCTestCase {
    func testHostPathToWindows() {
        let prefix = URL(fileURLWithPath: "/tmp/pfx")
        let host = URL(fileURLWithPath: "/tmp/pfx/drive_c/Program Files/App/run.exe")
        XCTAssertEqual(
            ShortcutScanner.hostPathToWindows(host, prefix: prefix),
            #"C:\Program Files\App\run.exe"#
        )
    }

    func testScansStartMenuAndDesktop() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("vermut-lnk-\(UUID().uuidString)", isDirectory: true)
        let start = prefix.appendingPathComponent("drive_c/ProgramData/Microsoft/Windows/Start Menu")
        let desktop = prefix.appendingPathComponent("drive_c/users/crossover/Desktop")
        try FileManager.default.createDirectory(at: start, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try Data().write(to: start.appendingPathComponent("Doom.lnk"))
        try Data().write(to: desktop.appendingPathComponent("Launcher.lnk"))
        try Data().write(to: desktop.appendingPathComponent("notes.txt"))
        defer { try? FileManager.default.removeItem(at: prefix) }

        let found = ShortcutScanner.scan(prefix: prefix)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains { $0.displayName == "Doom" && $0.locationLabel == "Start Menu" })
        XCTAssertTrue(found.contains { $0.displayName == "Launcher" && $0.locationLabel == "Desktop" })
    }
}


final class PrefixProcessTerminatorTests: XCTestCase {
    func testNativeMacSteamIsExcluded() {
        XCTAssertTrue(PrefixProcessTerminator.isNativeMacApp(
            "/Applications/Steam.app/Contents/MacOS/steam_osx"
        ))
        XCTAssertFalse(PrefixProcessTerminator.isNativeMacApp(
            "WINEPREFIX=/Users/x/Library/Application Support/Vermut/bottles/steam/prefix /wine steam.exe"
        ))
    }

    func testPidsOwningPrefixes() {
        let prefix = "/Users/x/Library/Application Support/Vermut/bottles/steam/prefix"
        let lines = [
            "100 /Applications/Steam.app/Contents/MacOS/steam_osx",
            "200 WINEPREFIX=\(prefix) /usr/local/bin/wine64 C:\\Steam\\steam.exe",
            "300 something unrelated"
        ]
        let pids = PrefixProcessTerminator.pids(
            owningPrefixes: [prefix],
            processLines: lines,
            currentPID: 1
        )
        XCTAssertEqual(pids, [200])
    }

    func testStopEscalationOrder() {
        var signals: [(pid_t, Int32)] = []
        var sleeps: [TimeInterval] = []
        var wineserverCalls = 0
        let prefix = "/tmp/vermut-prefix"
        let linesTerm = ["42 WINEPREFIX=\(prefix) wine64 steam.exe"]
        let linesAfterTerm: [String] = ["42 WINEPREFIX=\(prefix) wine64 steam.exe"]
        let linesAfterKill: [String] = []
        var phase = 0

        let leftover = PrefixProcessTerminator.stopAllVermutPrefixes(
            prefixes: [prefix],
            engineForPrefix: { _ in .grappleWine },
            options: .init(termGraceSeconds: 0.01, killGraceSeconds: 0.01, wineserverWaitSeconds: 0.01),
            sleeper: { sleeps.append($0) },
            signalSender: { pid, sig in
                signals.append((pid, sig))
                return 0
            },
            processLinesProvider: {
                defer { phase += 1 }
                if phase == 0 { return linesTerm }
                if phase == 1 { return linesAfterTerm }
                return linesAfterKill
            },
            wineserverRunner: { _, _ in wineserverCalls += 1 }
        )
        XCTAssertEqual(wineserverCalls, 1)
        XCTAssertEqual(signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertTrue(leftover.isEmpty)
        XCTAssertEqual(sleeps.count, 3)
    }
}

final class PathManagerCustomBottleTests: XCTestCase {
    func testCustomBottlePathsUseUUIDNotName() {
        let id = UUID()
        let manager = PathManager.shared
        let bottle = manager.customBottleURL(id: id)
        XCTAssertTrue(bottle.path.hasSuffix(id.uuidString))
        XCTAssertFalse(bottle.path.lowercased().contains("retro"))
        XCTAssertEqual(
            manager.customPrefixURL(id: id).lastPathComponent,
            "prefix"
        )
        XCTAssertTrue(manager.customLogURL(id: id).path.hasSuffix("bottle.log"))
    }
}

final class CustomBottleRequiredSpaceTests: XCTestCase {
    func testRequiredBytesIncludeOneGigHeadroom() {
        let required = WineManager.requiredFreeBytesForCreation(missingEngines: [])
        XCTAssertEqual(required, 1_000_000_000)
        let withStaging = WineManager.requiredFreeBytesForCreation(missingEngines: [.staging])
        XCTAssertGreaterThan(withStaging, required)
    }
}
