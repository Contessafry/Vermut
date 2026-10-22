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

    func testPidsIncludeBottleSteamWithoutPrefixEnvAndDescendants() {
        let steamPrefix = PathManager.shared.prefixURL(for: .steam).path
        let rows = [
            PrefixProcessTerminator.ProcessRow(
                pid: 10,
                ppid: 1,
                pgid: 10,
                command: "WINEPREFIX=\(steamPrefix) \(PathManager.shared.enginesURL.path)/grapple-wine/bin/wineserver"
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 20,
                ppid: 10,
                pgid: 10,
                command: #"C:\Program Files (x86)\Steam\steam.exe -silent"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 21,
                ppid: 20,
                pgid: 10,
                command: "steamwebhelper.exe --type=renderer"
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 30,
                ppid: 1,
                pgid: 30,
                command: "/Applications/Steam.app/Contents/MacOS/steam_osx"
            )
        ]
        let pids = PrefixProcessTerminator.pids(
            owningPrefixes: [steamPrefix],
            rows: rows,
            currentPID: 1
        )
        XCTAssertTrue(pids.contains(10))
        XCTAssertTrue(pids.contains(20))
        XCTAssertTrue(pids.contains(21))
        XCTAssertFalse(pids.contains(30))
    }

    func testSnapshotCapturesBareWindowsHelpersViaPgidAndVermutWineBinary() {
        let engines = PathManager.shared.enginesURL.path
        let wine64 = "\(engines)/grapple-wine/bin/wine64"
        let steamPrefix = PathManager.shared.prefixURL(for: .steam).path
        // After Steam exits, helpers often sit on launchd (ppid 1) with bare C:\ argv
        // and no WINEPREFIX — only pgid + Vermut wine executable still tie them to us.
        let rows = [
            PrefixProcessTerminator.ProcessRow(
                pid: 100,
                ppid: 1,
                pgid: 100,
                command: "WINEPREFIX=\(steamPrefix) \(engines)/grapple-wine/bin/wineserver"
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 101,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\services.exe"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 102,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\winedevice.exe"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 103,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\plugplay.exe"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 104,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\svchost.exe -k LocalService"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 105,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\explorer.exe /desktop"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 106,
                ppid: 1,
                pgid: 100,
                command: #"C:\windows\system32\rpcss.exe"#
            ),
            // Other Wine install — must not be claimed.
            PrefixProcessTerminator.ProcessRow(
                pid: 200,
                ppid: 1,
                pgid: 200,
                command: #"C:\windows\system32\services.exe"#
            )
        ]
        let exePaths: [pid_t: String] = [
            100: "\(engines)/grapple-wine/bin/wineserver",
            101: wine64, 102: wine64, 103: wine64, 104: wine64, 105: wine64, 106: wine64,
            200: "/opt/homebrew/bin/wine64"
        ]
        let snapped = PrefixProcessTerminator.snapshotPrefixPIDs(
            owningPrefixes: [steamPrefix],
            rows: rows,
            executablePathProvider: { exePaths[$0] },
            currentPID: 1
        )
        XCTAssertTrue(snapped.isSuperset(of: [100, 101, 102, 103, 104, 105, 106]))
        XCTAssertFalse(snapped.contains(200))
    }

    func testStopSignalsPreKillSnapshotEvenWhenHelpersLoseWINEPREFIX() {
        var signals: [(pid_t, Int32)] = []
        var wineserverTimeouts: [TimeInterval] = []
        let engines = PathManager.shared.enginesURL.path
        let wine64 = "\(engines)/grapple-wine/bin/wine64"
        // Use the real steam prefix path so discovery matches PathManager.
        let prefix = PathManager.shared.prefixURL(for: .steam).path
        let before = [
            PrefixProcessTerminator.ProcessRow(
                pid: 50,
                ppid: 1,
                pgid: 50,
                command: "WINEPREFIX=\(prefix) \(engines)/grapple-wine/bin/wineserver"
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 51,
                ppid: 1,
                pgid: 50,
                command: #"C:\windows\system32\services.exe"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 52,
                ppid: 1,
                pgid: 50,
                command: #"C:\windows\system32\winedevice.exe"#
            )
        ]
        // After wineserver -k: helpers still alive, still bare C:\…, no WINEPREFIX.
        let after = [
            PrefixProcessTerminator.ProcessRow(
                pid: 51,
                ppid: 1,
                pgid: 50,
                command: #"C:\windows\system32\services.exe"#
            ),
            PrefixProcessTerminator.ProcessRow(
                pid: 52,
                ppid: 1,
                pgid: 50,
                command: #"C:\windows\system32\winedevice.exe"#
            )
        ]
        var phase = 0
        let exePaths: [pid_t: String] = [
            50: "\(engines)/grapple-wine/bin/wineserver",
            51: wine64,
            52: wine64
        ]

        _ = PrefixProcessTerminator.stopAllVermutPrefixes(
            prefixes: [prefix],
            engineForPrefix: { _ in .grappleWine },
            options: .init(
                termGraceSeconds: 0.01,
                killGraceSeconds: 0.01,
                wineserverKillTimeout: 2.0,
                afterWineserverSeconds: 0.01
            ),
            sleeper: { _ in },
            signalSender: { pid, sig in
                signals.append((pid, sig))
                return 0
            },
            processLinesProvider: { [] },
            processRowsProvider: {
                defer { phase += 1 }
                // phase 0: pre-kill snapshot; later phases: post-kill (no wineserver).
                return phase == 0 ? before : after
            },
            executablePathProvider: { exePaths[$0] },
            wineserverRunner: { _, _, timeout in
                wineserverTimeouts.append(timeout)
            }
        )
        XCTAssertEqual(wineserverTimeouts, [2.0])
        let termPIDs = Set(signals.filter { $0.1 == SIGTERM }.map(\.0))
        let killPIDs = Set(signals.filter { $0.1 == SIGKILL }.map(\.0))
        XCTAssertTrue(termPIDs.isSuperset(of: [50, 51, 52]), "pre-kill snapshot must be SIGTERM’d: \(termPIDs)")
        XCTAssertTrue(killPIDs.isSuperset(of: [50, 51, 52]), "pre-kill snapshot must be SIGKILL’d: \(killPIDs)")
    }

    func testStopEscalationOrderUsesBoundedWineserver() {
        var signals: [(pid_t, Int32)] = []
        var sleeps: [TimeInterval] = []
        var wineserverTimeouts: [TimeInterval] = []
        let prefix = "/tmp/vermut-prefix"
        let rowsTerm = [
            PrefixProcessTerminator.ProcessRow(pid: 42, ppid: 1, pgid: 42, command: "WINEPREFIX=\(prefix) wine64 steam.exe")
        ]
        let rowsAfterTerm = rowsTerm
        let rowsAfterKill: [PrefixProcessTerminator.ProcessRow] = []
        var phase = 0

        let leftover = PrefixProcessTerminator.stopAllVermutPrefixes(
            prefixes: [prefix],
            engineForPrefix: { _ in .grappleWine },
            options: .init(
                termGraceSeconds: 0.01,
                killGraceSeconds: 0.01,
                wineserverKillTimeout: 2.5,
                afterWineserverSeconds: 0.01
            ),
            sleeper: { sleeps.append($0) },
            signalSender: { pid, sig in
                signals.append((pid, sig))
                return 0
            },
            processLinesProvider: { [] },
            processRowsProvider: {
                defer { phase += 1 }
                if phase == 0 { return rowsTerm }
                if phase == 1 { return rowsAfterTerm }
                return rowsAfterKill
            },
            wineserverRunner: { _, _, timeout in
                wineserverTimeouts.append(timeout)
            }
        )
        XCTAssertEqual(wineserverTimeouts, [2.5])
        XCTAssertEqual(signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertTrue(leftover.isEmpty)
        XCTAssertEqual(sleeps.count, 3)
    }

    func testIsVermutWineExecutable() {
        let engines = PathManager.shared.enginesURL.path
        XCTAssertTrue(PrefixProcessTerminator.isVermutWineExecutable("\(engines)/grapple-wine/bin/wine64"))
        XCTAssertTrue(PrefixProcessTerminator.isVermutWineExecutable("\(engines)/staging/bin/wineserver"))
        XCTAssertFalse(PrefixProcessTerminator.isVermutWineExecutable("/opt/homebrew/bin/wine64"))
        XCTAssertFalse(PrefixProcessTerminator.isVermutWineExecutable("/Applications/Steam.app/Contents/MacOS/steam_osx"))
    }

    func testCommandBelongsMatchesBottlesPath() {
        let bottles = PathManager.shared.bottlesURL.path
        XCTAssertTrue(
            PrefixProcessTerminator.commandBelongsToPrefixes(
                "WINEPREFIX=\(bottles)/steam/prefix wine64",
                prefixes: ["\(bottles)/steam/prefix"],
                includesSteamBottle: true
            )
        )
        XCTAssertFalse(
            PrefixProcessTerminator.commandBelongsToPrefixes(
                "/Applications/Steam.app/Contents/MacOS/steam_osx",
                prefixes: ["\(bottles)/steam/prefix"],
                includesSteamBottle: true
            )
        )
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
