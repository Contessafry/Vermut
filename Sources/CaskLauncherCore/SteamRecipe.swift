import Foundation

/// Wine `reg add` write. Kept as data so prefix policy is unit-testable without Wine.
public struct WineRegWrite: Equatable, Sendable {
    public var key: String
    public var value: String
    public var data: String
    public var type: String

    public init(key: String, value: String, data: String, type: String = "REG_SZ") {
        self.key = key
        self.value = value
        self.data = data
        self.type = type
    }

    public var argv: [String] {
        ["reg", "add", key, "/v", value, "/t", type, "/d", data, "/f"]
    }
}

public enum WineRegOp: Equatable, Sendable {
    case add(WineRegWrite)
    case deleteKey(String)
    case deleteValue(key: String, value: String)

    public var argv: [String] {
        switch self {
        case .add(let write):
            return write.argv
        case .deleteKey(let key):
            return ["reg", "delete", key, "/f"]
        case .deleteValue(let key, let value):
            return ["reg", "delete", key, "/v", value, "/f"]
        }
    }

    public var added: WineRegWrite? {
        if case .add(let write) = self { return write }
        return nil
    }
}

/// Per-engine DLL override policy. Native DXMT is only valid on grapple-wine.
public enum DllOverridePolicy {
    public static let dxmtLibraries = ["d3d11", "dxgi", "d3d10core", "winemetal"]
    public static let steamWebHelper = "steamwebhelper.exe"
    public static let globalDllOverridesKey = "HKCU\\Software\\Wine\\DllOverrides"
    /// Must use `\\` concatenation: a raw `\#(` is Swift interpolation, not a path slash.
    public static let steamWebHelperAppKey =
        "HKCU\\Software\\Wine\\AppDefaults\\" + steamWebHelper + "\\DllOverrides"
    /// Typo from the raw-string interpolation bug (`AppDefaults` glued to the exe name).
    public static let brokenSteamWebHelperKey =
        "HKCU\\Software\\Wine\\AppDefaults" + steamWebHelper

    public static func usesNativeDXMT(
        engine: WineEngine,
        backend: GraphicsBackend,
        store: GameStore = .steam
    ) -> Bool {
        StoreRecipe.allowsNativeGraphics(store) && engine.supportsDXMT && backend == .dxmt
    }

    public static func cefHelperExecutables(for store: GameStore) -> [String] {
        switch store {
        case .steam: return [steamWebHelper]
        case .epic: return ["EpicWebHelper.exe"]
        case .gog: return ["GalaxyClient Helper.exe", "GalaxyClient.exe"]
        }
    }

    public static func appDefaultsDllOverridesKey(executable: String) -> String {
        "HKCU\\Software\\Wine\\AppDefaults\\" + executable + "\\DllOverrides"
    }

    /// Global `HKCU\Software\Wine\DllOverrides` for D3D / winemetal.
    /// Grapple-wine Steam/Epic DXMT bottles leave D3D keys empty.
    /// DXVK needs native D3D plus builtin `vulkan-1`/`winevulkan` (never `d`).
    /// GOG stays builtin. Staging/devel never get native DXMT.
    public static func globalGraphicsOverrides(
        engine: WineEngine,
        backend: GraphicsBackend,
        store: GameStore = .steam
    ) -> [String: String] {
        if backend == .dxvk {
            var map: [String: String] = [:]
            for name in EpicVulkanPolicy.dxvkNativeLibraries {
                map[name] = "native"
            }
            for name in EpicVulkanPolicy.vulkanLibraries {
                map[name] = "builtin"
            }
            return map
        }
        if !StoreRecipe.allowsNativeGraphics(store) {
            return Dictionary(uniqueKeysWithValues: dxmtLibraries.map { ($0, "builtin") })
        }
        if engine.supportsDXMT {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: dxmtLibraries.map { ($0, "builtin") })
    }

    /// Steam's Chromium helper must stay on Wine builtin D3D, even when games use DXMT.
    public static func steamWebHelperOverrides() -> [String: String] {
        Dictionary(uniqueKeysWithValues: dxmtLibraries.map { ($0, "builtin") })
    }

    public static func steamWebHelperOverrideString() -> String {
        "d3d11,dxgi,d3d10core,winemetal=builtin"
    }

    /// Shown on the bottle General tab. Internal identifiers stay out of copy.
    public static func userFacingSummary(
        engine: WineEngine,
        backend: GraphicsBackend,
        store: GameStore
    ) -> String {
        if backend == .dxvk {
            return "DXVK native, Vulkan built-in"
        }
        let globals = globalGraphicsOverrides(engine: engine, backend: backend, store: store)
        if globals.isEmpty {
            return "Engine default"
        }
        return globals.keys.sorted().joined(separator: ", ") + " = built-in"
    }

    public static func registryWrites(
        engine: WineEngine,
        backend: GraphicsBackend,
        store: GameStore
    ) -> [WineRegOp] {
        var ops: [WineRegOp] = []
        let globals = globalGraphicsOverrides(engine: engine, backend: backend, store: store)
        for name in dxmtLibraries {
            guard let data = globals[name] else { continue }
            ops.append(.add(WineRegWrite(key: globalDllOverridesKey, value: name, data: data)))
        }

        if store != .epic {
            for helper in cefHelperExecutables(for: store) {
                let key = appDefaultsDllOverridesKey(executable: helper)
                for name in dxmtLibraries {
                    ops.append(.add(WineRegWrite(key: key, value: name, data: "builtin")))
                }
            }
        }
        if store == .epic {
            ops.append(contentsOf: EpicVulkanPolicy.registryWrites(backend: backend))
        }

        if store == .steam || store == .epic || store == .gog {
            ops.append(
                .add(WineRegWrite(
                    key: "HKCU\\Software\\Wine\\Mac Driver",
                    value: "RetinaMode",
                    data: "n"
                ))
            )
        }
        if store == .gog {
            ops.append(contentsOf: GOGRecipe.registryWrites())
        }
        return ops
    }
}

/// Launch argv + env for a store. Steam flags come from behavioural testing, not Grapple source.
public struct StoreLaunchRecipe: Equatable, Sendable {
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?

    public init(arguments: [String], environment: [String: String], workingDirectory: String? = nil) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    /// Steam always follows the app default engine, not a leftover bottle engine.
    public static func engine(
        for store: GameStore,
        defaultEngine: String,
        bottleEngine: String
    ) -> WineEngine {
        if store == .steam {
            return WineEngine.resolved(from: defaultEngine)
        }
        return WineEngine.resolved(from: bottleEngine)
    }

    /// Epic keeps `err` so DXVK/Win64 page faults show up in the bottle log.
    public static let epicWineDebug = "err+all,fixme-all"

    public static func launchLogLine(
        store: GameStore,
        engine: WineEngine,
        wine: URL,
        wineserver: URL
    ) -> String {
        "Vermut: launching \(store.identifier) with engine=\(engine.rawValue) wine=\(wine.path) wineserver=\(wineserver.path)"
    }

    /// Keys logged at launch for Mac QA diffs. No secrets / tokens / home paths beyond Wine paths.
    public static let launchEnvironmentLogKeys: [String] = [
        "WINEPREFIX",
        "WINELOADER",
        "WINESERVER",
        "WINEDLLPATH",
        "WINEDEBUG",
        "WINEESYNC",
        "WINEMSYNC",
        "WINEDLLOVERRIDES",
        "WINEARCH",
        "PATH"
    ]

    /// One capped bottle-log line: resolved engine root + selected Wine env (PATH summarized).
    public static func launchEnvironmentSummary(
        engineRoot: URL,
        wine: URL,
        environment: [String: String]
    ) -> String {
        var parts: [String] = [
            "Vermut: launch-env",
            "engineRoot=\(engineRoot.path)",
            "wine=\(wine.path)"
        ]
        for key in launchEnvironmentLogKeys.sorted() {
            guard let raw = environment[key] else { continue }
            if key == "PATH" {
                parts.append("PATH=\(summarizeLaunchPATH(raw, wineBin: wine.deletingLastPathComponent().path))")
            } else {
                parts.append("\(key)=\(raw)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Whether the Wine `bin` directory leads PATH (avoids dumping the full host PATH).
    public static func summarizeLaunchPATH(_ path: String, wineBin: String) -> String {
        let entries = path.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = entries.first else { return "(empty)" }
        if first == wineBin || path.hasPrefix(wineBin + ":") {
            return "wine-bin-first+\(max(0, entries.count - 1))-more"
        }
        return "wine-bin-not-first first=\(first)"
    }

    public static let syncEnvironmentKeys = ["WINEESYNC", "WINEMSYNC"]

    /// Sync mode a store runs with. Every wine process sharing the prefix's
    /// wineserver must use the same values.
    public static func syncEnvironment(for store: GameStore) -> [String: String] {
        store == .steam ? ["WINEESYNC": "1", "WINEMSYNC": "1"] : [:]
    }

    /// Wine DLL override that disables Steam's in-process overlay.
    public static let steamOverlayDisableOverride = "gameoverlayrenderer,gameoverlayrenderer64=d"

    public static func build(
        store: GameStore,
        executable: URL,
        wineLibDir: URL,
        firstRunUpdate: Bool = false,
        steamAppId: String? = nil,
        steamOverlayEnabled: Bool = false
    ) -> StoreLaunchRecipe {
        var env: [String: String] = [
            "WINEDEBUG": "-all",
            "WINEDLLPATH": wineLibDir.path
        ]

        for (key, value) in syncEnvironment(for: store) { env[key] = value }
        switch store {
        case .steam:
            env["ROSETTA_ADVERTISE_AVX"] = "1"
            env["CX_FWD_COMPAT_GL_CTX"] = "1"
            if !steamOverlayEnabled {
                env["WINEDLLOVERRIDES"] = steamOverlayDisableOverride
                env["SteamNoOverlay"] = "1"
            }
            let arguments: [String]
            if let steamAppId, !steamAppId.isEmpty {
                arguments = SteamGameLaunch.applaunchArguments(
                    appId: steamAppId,
                    firstRunUpdate: firstRunUpdate
                )
            } else if firstRunUpdate {
                arguments = ["steam.exe"]
            } else {
                arguments = ["steam.exe", "-no-cef-sandbox", "-cef-disable-gpu", "-noverifyfiles"]
            }
            return StoreLaunchRecipe(
                // First run: plain steam.exe so the bootstrapper downloads and
                // applies the client normally (msync env fix still applies).
                // Play: steam.exe … -applaunch <appId> so the title starts (not only the client).
                arguments: arguments,
                environment: env,
                workingDirectory: executable.deletingLastPathComponent().path
            )
        case .epic:
            env["WINEARCH"] = "win64"
            env["WINEDEBUG"] = epicWineDebug
            return StoreLaunchRecipe(
                arguments: [],
                environment: env,
                workingDirectory: nil
            )
        case .gog:
            env["WINEDLLOVERRIDES"] = GOGRecipe.dllOverrides
            GOGRecipe.applySoftwareEnvironment(to: &env)
            return StoreLaunchRecipe(
                arguments: [executable.lastPathComponent] + GOGRecipe.launchArguments,
                environment: env,
                workingDirectory: executable.deletingLastPathComponent().path
            )
        }
    }
}

/// Minimal parser for Wine `user.reg` so Steam bottle migration can be tested without Wine.
public enum WineUserRegParser {
    public static func values(in contents: String, sectionSuffix: String) -> [String: String] {
        var currentSection: String?
        var result: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if !result.isEmpty, currentSection?.contains(sectionSuffix) == true {
                    return result
                }
                currentSection = line
                if line.contains(sectionSuffix) {
                    result = [:]
                }
                continue
            }
            guard currentSection?.contains(sectionSuffix) == true else { continue }
            guard let parsed = parseQuotedPair(line) else { continue }
            result[parsed.0] = parsed.1
        }
        return result
    }

    public static func dllOverrides(in contents: String) -> [String: String] {
        values(in: contents, sectionSuffix: #"Software\\Wine\\DllOverrides]"#)
    }

    public static func retinaMode(in contents: String) -> String? {
        values(in: contents, sectionSuffix: #"Software\\Wine\\Mac Driver]"#)["RetinaMode"]
    }

    public static func hasBrokenSteamWebHelperKey(_ contents: String) -> Bool {
        contents.contains("AppDefaultssteamwebhelper.exe")
    }

    private static func parseQuotedPair(_ line: String) -> (String, String)? {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let key = unquote(parts[0])
        let value = unquote(parts[1])
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private static func unquote(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("\"") { s.removeFirst() }
        if s.hasSuffix("\"") { s.removeLast() }
        return s
    }
}

/// Fixes leftover Steam bottles from earlier CaskLauncher builds (native CEF, Retina, wrappers).
public enum SteamBottleMigration {
    public static func needsFix(
        userReg: String,
        engine: WineEngine,
        backend: GraphicsBackend
    ) -> Bool {
        !writes(userReg: userReg, engine: engine, backend: backend).isEmpty
    }

    public static func writes(
        userReg: String,
        engine: WineEngine,
        backend: GraphicsBackend
    ) -> [WineRegOp] {
        var ops: [WineRegOp] = []
        let current = WineUserRegParser.dllOverrides(in: userReg)
        let desired = DllOverridePolicy.globalGraphicsOverrides(engine: engine, backend: backend, store: .steam)
        let retina = WineUserRegParser.retinaMode(in: userReg)

        if WineUserRegParser.hasBrokenSteamWebHelperKey(userReg) {
            ops.append(.deleteKey(DllOverridePolicy.brokenSteamWebHelperKey))
        }

        if engine.supportsDXMT {
            for name in DllOverridePolicy.dxmtLibraries where current[name] != nil {
                ops.append(.deleteValue(key: DllOverridePolicy.globalDllOverridesKey, value: name))
            }
        } else {
            let hasGlobalNative = DllOverridePolicy.dxmtLibraries.contains {
                current[$0]?.lowercased() == "native"
            }
            if hasGlobalNative {
                for name in DllOverridePolicy.dxmtLibraries {
                    ops.append(.add(WineRegWrite(
                        key: DllOverridePolicy.globalDllOverridesKey,
                        value: name,
                        data: desired[name] ?? "builtin"
                    )))
                }
            }
        }

        if retina?.lowercased() == "y" {
            ops.append(.add(WineRegWrite(
                key: "HKCU\\Software\\Wine\\Mac Driver",
                value: "RetinaMode",
                data: "n"
            )))
        }

        ops.append(contentsOf: DllOverridePolicy.registryWrites(
            engine: engine,
            backend: backend,
            store: .steam
        ).filter {
            if case .add(let write) = $0 {
                return write.key.contains("AppDefaults\\")
            }
            return false
        })

        return ops
    }
}

/// Copy plan so DXMT's unix `winemetal.so` lands in the engine's `x86_64-unix` dir.
public enum DXMTUnixLib {
    public static let fileName = "winemetal.so"

    public static func source(in overlay: OverlayLayout) -> URL? {
        overlay.unix64Dir?.appendingPathComponent(fileName)
    }

    public static func destination(in engine: EngineLayout) -> URL? {
        engine.unix64Dir?.appendingPathComponent(fileName)
    }

    public static func needsInstall(
        overlay: OverlayLayout,
        engine: EngineLayout,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let src = source(in: overlay), let dest = destination(in: engine) else {
            return false
        }
        return fileManager.fileExists(atPath: src.path) && !fileManager.fileExists(atPath: dest.path)
    }

    public static func installIfNeeded(
        overlay: OverlayLayout,
        engine: EngineLayout,
        fileManager: FileManager = .default
    ) throws {
        guard needsInstall(overlay: overlay, engine: engine, fileManager: fileManager),
              let src = source(in: overlay),
              let dest = destination(in: engine)
        else { return }
        try fileManager.copyItem(at: src, to: dest)
    }
}

public enum DXMTWindowsDLLs {
    public static let names = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]

    public static func copyPlan(
        overlay: OverlayLayout,
        system32: URL,
        syswow64: URL
    ) -> [(from: URL, to: URL)] {
        var plan: [(URL, URL)] = []
        if let win64 = overlay.windows64Dir {
            for name in names {
                plan.append((win64.appendingPathComponent(name), system32.appendingPathComponent(name)))
            }
        }
        if let win32 = overlay.windows32Dir {
            for name in names {
                plan.append((win32.appendingPathComponent(name), syswow64.appendingPathComponent(name)))
            }
        }
        return plan
    }
}
