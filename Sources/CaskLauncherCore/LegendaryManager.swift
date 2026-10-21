import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Native Legendary CLI (GPLv3). Runs on the host, never under Wine.
/// Binary: `engines/legendary/legendary`. Config: the Epic bottle's `legendary/` folder.
public enum LegendaryCLI {
    public static let windowsPlatform = "Windows"
    public static let loginPageURL = URL(string: "https://legendary.gl/epiclogin")!
    public static let sourceURL = URL(string: "https://github.com/derrod/legendary")!
    public static let licenceName = "GPLv3"

    public static func authCodeArguments(_ code: String) -> [String] {
        ["auth", "--code", code, "--disable-webview"]
    }

    public static func logoutArguments() -> [String] {
        ["auth", "--delete"]
    }

    public static func listOwnedArguments() -> [String] {
        ["list", "--json", "--platform", windowsPlatform]
    }

    public static func listInstalledArguments() -> [String] {
        ["list-installed", "--json", "--platform", windowsPlatform]
    }

    public static func statusArguments() -> [String] {
        ["status", "--json", "--offline"]
    }

    public static func installArguments(appName: String, basePath: String) -> [String] {
        ["install", appName, "--base-path", basePath, "-y", "--platform", windowsPlatform]
    }

    public static func launchArguments(appName: String, wine: String, prefix: String) -> [String] {
        ["launch", appName, "--wine", wine, "--wine-prefix", prefix]
    }
}

/// Store-card copy. Keep the blurb to two short lines at card width.
public enum EpicStoreCopy {
    public static let blurb = "Your Epic library, via Legendary. Windows games run in this bottle."
    public static let signedOutBadge = "Signed out"
    public static let signedInDescription = "Games install into this bottle and launch with Legendary."
    public static let graphicsHelp = "DXMT on Vermut Wine, or DXVK on Wine Staging (Vermut Wine has no Vulkan loader)"

    public static func signedInBadge(account: String) -> String {
        "Signed in · \(account)"
    }

    public static func badge(isLoggedIn: Bool, account: String?) -> String {
        if isLoggedIn, let account, !account.isEmpty {
            return signedInBadge(account: account)
        }
        return signedOutBadge
    }
}

public struct LegendaryAccount: Equatable, Sendable {
    public var displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }
}

public struct LegendaryGame: Equatable, Sendable {
    public var appName: String
    public var title: String
    public var isInstalled: Bool
    public var installPath: String?
    public var isDLC: Bool
    public var coverURLs: [URL]

    public init(
        appName: String,
        title: String,
        isInstalled: Bool = false,
        installPath: String? = nil,
        isDLC: Bool = false,
        coverURLs: [URL] = []
    ) {
        self.appName = appName
        self.title = title
        self.isInstalled = isInstalled
        self.installPath = installPath
        self.isDLC = isDLC
        self.coverURLs = coverURLs
    }

    public func asInstalledGame() -> InstalledGame {
        InstalledGame(
            store: .epic,
            appId: appName,
            name: title,
            installDir: installPath,
            coverURLs: coverURLs,
            isInstalled: isInstalled
        )
    }
}

public enum LegendaryError: LocalizedError, Equatable {
    case binaryMissing
    case notLoggedIn
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "Legendary is not installed yet."
        case .notLoggedIn:
            return "Sign in to Epic Games to continue."
        case .failed(let message):
            return message
        case .cancelled:
            return "Installation cancelled"
        }
    }
}

/// Parses Legendary JSON / log lines. Pure so Linux tests do not need the binary.
public enum LegendaryParse {
    public static func authorizationCode(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromJSON = codeFromJSONObject(trimmed) { return fromJSON }
        if let fromURL = codeFromURL(trimmed) { return fromURL }
        if let fromRegex = codeFromQuotedField(trimmed) { return fromRegex }
        return nil
    }

    public static func authorizationCode(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where item.name == "authorizationCode" || item.name == "code" {
                if let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    return value
                }
            }
        }
        if let fragment = url.fragment, let code = authorizationCode(in: fragment) {
            return code
        }
        return authorizationCode(in: url.absoluteString)
    }

    public static func parseOwned(data: Data) -> [LegendaryGame] {
        guard let root = jsonArray(in: data) else { return [] }
        return root.compactMap { object in
            let appName = string(object["app_name"]) ?? ""
            let title = string(object["app_title"]) ?? string(object["title"]) ?? ""
            guard !appName.isEmpty, !title.isEmpty else { return nil }
            let metadata = object["metadata"] as? [String: Any] ?? [:]
            let isDLC = object["is_dlc"] as? Bool == true || metadata["mainGameItem"] != nil
            return LegendaryGame(
                appName: appName,
                title: title,
                isInstalled: false,
                installPath: nil,
                isDLC: isDLC,
                coverURLs: coverURLs(from: metadata)
            )
        }
    }

    public static func parseInstalled(data: Data) -> [LegendaryGame] {
        guard let root = jsonArray(in: data) else { return [] }
        return root.compactMap { object in
            let appName = string(object["app_name"]) ?? ""
            let title = string(object["title"]) ?? string(object["app_title"]) ?? ""
            guard !appName.isEmpty, !title.isEmpty else { return nil }
            return LegendaryGame(
                appName: appName,
                title: title,
                isInstalled: true,
                installPath: string(object["install_path"]),
                isDLC: object["is_dlc"] as? Bool == true,
                coverURLs: []
            )
        }
    }

    public static func merge(owned: [LegendaryGame], installed: [LegendaryGame]) -> [LegendaryGame] {
        var installedByApp = Dictionary(uniqueKeysWithValues: installed.map { ($0.appName, $0) })
        var result: [LegendaryGame] = []
        var seen = Set<String>()
        for game in owned where !game.isDLC {
            var merged = game
            if let local = installedByApp.removeValue(forKey: game.appName) {
                merged.isInstalled = true
                merged.installPath = local.installPath
            }
            result.append(merged)
            seen.insert(game.appName)
        }
        for leftover in installedByApp.values where !leftover.isDLC && seen.insert(leftover.appName).inserted {
            result.append(leftover)
        }
        return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public static func parseAccount(statusJSON data: Data) -> LegendaryAccount? {
        guard let object = jsonObject(in: data) else { return nil }
        let name = (string(object["account"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != " " else { return nil }
        return LegendaryAccount(displayName: name)
    }

    public static func parseUserJSON(_ data: Data) -> LegendaryAccount? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let name = (string(object["displayName"]) ?? string(object["DisplayName"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return LegendaryAccount(displayName: name)
    }

    public static func coverURLs(from metadata: [String: Any]) -> [URL] {
        let images = metadata["keyImages"] as? [[String: Any]] ?? []
        func urls(matching type: String) -> [URL] {
            images.compactMap { image in
                let imageType = string(image["type"]) ?? ""
                guard imageType.caseInsensitiveCompare(type) == .orderedSame else { return nil }
                return string(image["url"]).flatMap(URL.init(string:))
            }
        }
        var result: [URL] = []
        var seen = Set<String>()
        for type in ["DieselGameBoxTall", "Thumbnail", "DieselGameBox", "OfferImageTall"] {
            for url in urls(matching: type) where seen.insert(url.absoluteString).inserted {
                result.append(url)
            }
        }
        return result
    }

    public static func progressFraction(in line: String) -> Double? {
        let patterns = [
            #"\[DL\]\s+(\d+(?:\.\d+)?)%"#,
            #"Progress:\s+(\d+(?:\.\d+)?)%"#,
            #"=\s*Progress:\s+(\d+(?:\.\d+)?)%"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges > 1,
               let swiftRange = Range(match.range(at: 1), in: line),
               let value = Double(line[swiftRange]) {
                return min(max(value / 100.0, 0), 1)
            }
        }
        return nil
    }

    /// JSON payload may be preceded by log lines on a merged stream.
    public static func jsonPayload(in text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let slice = String(trimmed[start...])
            if let data = slice.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        return trimmed.data(using: .utf8)
    }

    private static func codeFromJSONObject(_ text: String) -> String? {
        guard let data = jsonPayload(in: text),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if let code = string(object["authorizationCode"]), !code.isEmpty { return code }
        if let nested = object["data"] as? [String: Any],
           let code = string(nested["authorizationCode"]), !code.isEmpty {
            return code
        }
        return nil
    }

    private static func codeFromQuotedField(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #""authorizationCode"\s*:\s*"([^"]+)""#
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let code = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    private static func codeFromURL(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://") || trimmed.contains("authorizationCode=") || trimmed.contains("?code=") else {
            return nil
        }
        guard let url = URL(string: trimmed) else { return nil }
        return authorizationCode(from: url)
    }

    private static func jsonArray(in data: Data) -> [[String: Any]]? {
        if let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            return array
        }
        if let text = String(data: data, encoding: .utf8),
           let payload = jsonPayload(in: text),
           let array = (try? JSONSerialization.jsonObject(with: payload)) as? [[String: Any]] {
            return array
        }
        return nil
    }

    private static func jsonObject(in data: Data) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return object
        }
        if let text = String(data: data, encoding: .utf8),
           let payload = jsonPayload(in: text),
           let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] {
            return object
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

/// DXVK needs Wine's Vulkan loader (`builtin`), never `disabled`.
public enum EpicVulkanPolicy {
    public static let vulkanLibraries = ["vulkan-1", "winevulkan"]
    public static let dxvkNativeLibraries = ["d3d9", "d3d10core", "d3d11", "dxgi"]

    /// `WINEDLLOVERRIDES` for a DXVK game. Native D3D, builtin Vulkan.
    public static let dxvkOverrideString = "d3d9,d3d10core,d3d11,dxgi=n;vulkan-1,winevulkan=b"

    public static func registryWrites(backend: GraphicsBackend) -> [WineRegOp] {
        var ops: [WineRegOp] = []
        if backend == .dxvk {
            for name in dxvkNativeLibraries {
                ops.append(.add(WineRegWrite(
                    key: DllOverridePolicy.globalDllOverridesKey,
                    value: name,
                    data: "native"
                )))
            }
            for name in vulkanLibraries {
                ops.append(.add(WineRegWrite(
                    key: DllOverridePolicy.globalDllOverridesKey,
                    value: name,
                    data: "builtin"
                )))
            }
        } else {
            for name in vulkanLibraries {
                ops.append(.deleteValue(key: DllOverridePolicy.globalDllOverridesKey, value: name))
            }
        }
        return ops
    }

    public static func leftoverDisabledVulkanWrites(userReg: String, backend: GraphicsBackend) -> [WineRegOp] {
        let current = WineUserRegParser.dllOverrides(in: userReg)
        let hasDisabled = vulkanLibraries.contains {
            current[$0]?.lowercased() == "d" || current[$0]?.lowercased() == "disabled"
        }
        guard hasDisabled || backend == .dxvk else { return [] }
        return registryWrites(backend: backend)
    }
}

public final class LegendaryManager: @unchecked Sendable {
    public static let shared = LegendaryManager()

    private let fileManager: FileManager
    private let lock = NSLock()
    private var installProcess: Process?

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func binaryURL() -> URL {
        PathManager.shared.legendaryBinaryURL
    }

    public func configDirectory() -> URL {
        PathManager.shared.legendaryConfigURL
    }

    public func gamesBasePath() -> URL {
        PathManager.shared.prefixURL(for: .epic).appendingPathComponent("drive_c/Games")
    }

    public func isBinaryInstalled() -> Bool {
        fileManager.isExecutableFile(atPath: binaryURL().path)
            || fileManager.fileExists(atPath: binaryURL().path)
    }

    public func isLoggedIn() -> Bool {
        account() != nil
    }

    public func account() -> LegendaryAccount? {
        let userJSON = configDirectory().appendingPathComponent("user.json")
        guard let data = try? Data(contentsOf: userJSON) else { return nil }
        return LegendaryParse.parseUserJSON(data)
    }

    public func processEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["LEGENDARY_CONFIG_PATH"] = configDirectory().path
        env["PYTHONUNBUFFERED"] = "1"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    public func ensureBinary(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if isBinaryInstalled() {
            progress(1)
            return
        }
        let resolved = await ComponentCatalog.resolveLegendary()
        let cache = PathManager.shared.cacheURL.appendingPathComponent(resolved.filename)
        try await DownloadClient.download(
            from: resolved.url,
            to: cache,
            expectedSHA256: resolved.sha256,
            progress: progress
        )
        try installBinary(from: cache, filename: resolved.filename)
    }

    public func login(code: String) throws -> LegendaryAccount {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LegendaryError.failed("Missing Epic authorization code.") }
        try ensureConfigDirectory()
        let result = try run(LegendaryCLI.authCodeArguments(trimmed))
        if result.status != 0 {
            throw LegendaryError.failed(cleanError(result.stderr, stdout: result.stdout, fallback: "Epic sign-in failed."))
        }
        if let account = account() { return account }
        if let fromStatus = try? parseStatusAccount() { return fromStatus }
        throw LegendaryError.failed("Signed in, but Legendary did not write an account name.")
    }

    public func logout() throws {
        guard isBinaryInstalled() else { return }
        _ = try? run(LegendaryCLI.logoutArguments())
        let userJSON = configDirectory().appendingPathComponent("user.json")
        try? fileManager.removeItem(at: userJSON)
    }

    public func libraryGames() throws -> [InstalledGame] {
        guard isLoggedIn() else { return [] }
        let ownedData = try runJSON(LegendaryCLI.listOwnedArguments())
        let installedData = try runJSON(LegendaryCLI.listInstalledArguments())
        let merged = LegendaryParse.merge(
            owned: LegendaryParse.parseOwned(data: ownedData),
            installed: LegendaryParse.parseInstalled(data: installedData)
        )
        return merged.map { $0.asInstalledGame() }
    }

    public func install(
        appName: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws {
        try ensureConfigDirectory()
        let base = gamesBasePath()
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let args = LegendaryCLI.installArguments(appName: appName, basePath: base.path)
        let status = try runStreaming(args) { line in
            if let fraction = LegendaryParse.progressFraction(in: line) {
                progress(fraction, line)
            }
        }
        if status == SIGTERM || status == SIGKILL { throw LegendaryError.cancelled }
        if status != 0 { throw LegendaryError.failed("Legendary install failed (exit \(status)).") }
        progress(1, "Installed")
    }

    public func cancelInstall() {
        lock.lock()
        let process = installProcess
        installProcess = nil
        lock.unlock()
        process?.terminate()
    }

    public func launch(
        appName: String,
        wine: URL,
        prefix: URL,
        extraEnvironment: [String: String]
    ) throws {
        try ensureConfigDirectory()
        let args = LegendaryCLI.launchArguments(
            appName: appName,
            wine: wine.path,
            prefix: prefix.path
        )
        var env = processEnvironment(extra: extraEnvironment)
        env["WINEPREFIX"] = prefix.path
        env["WINELOADER"] = wine.path
        try spawnDetached(arguments: args, environment: env)
    }

    func installBinary(from cache: URL, filename: String) throws {
        let destDir = binaryURL().deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: binaryURL().path) {
            try fileManager.removeItem(at: binaryURL())
        }
        if filename.lowercased().hasSuffix(".zip") {
            try unzipLegendary(from: cache, into: destDir)
        } else {
            try fileManager.copyItem(at: cache, to: binaryURL())
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryURL().path
        )
        #if os(macOS)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.quarantine", binaryURL().path]
        xattr.standardOutput = FileHandle.nullDevice
        xattr.standardError = FileHandle.nullDevice
        try? xattr.run()
        xattr.waitUntilExit()
        #endif
    }

    private func unzipLegendary(from zip: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zip.path, "-d", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LegendaryError.failed("Could not unpack Legendary.")
        }
        if fileManager.fileExists(atPath: binaryURL().path) { return }
        let items = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if let found = items.first(where: { $0.lastPathComponent.lowercased().hasPrefix("legendary") }) {
            if found != binaryURL() {
                try fileManager.moveItem(at: found, to: binaryURL())
            }
        }
    }

    private func ensureConfigDirectory() throws {
        try fileManager.createDirectory(at: configDirectory(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gamesBasePath(), withIntermediateDirectories: true)
    }

    private func parseStatusAccount() throws -> LegendaryAccount? {
        let result = try run(LegendaryCLI.statusArguments())
        guard let data = LegendaryParse.jsonPayload(in: result.stdout)
                ?? LegendaryParse.jsonPayload(in: result.stderr)
        else { return nil }
        return LegendaryParse.parseAccount(statusJSON: data)
    }

    private func runJSON(_ arguments: [String]) throws -> Data {
        let result = try run(arguments)
        if result.status != 0 {
            throw LegendaryError.failed(cleanError(result.stderr, stdout: result.stdout, fallback: "Legendary command failed."))
        }
        if let data = LegendaryParse.jsonPayload(in: result.stdout) { return data }
        if let data = LegendaryParse.jsonPayload(in: result.stderr) { return data }
        throw LegendaryError.failed("Legendary returned no JSON.")
    }

    private func run(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        guard isBinaryInstalled() else { throw LegendaryError.binaryMissing }
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = arguments
        process.environment = processEnvironment()
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(data: ProcessPipe.readToEnd(out.fileHandleForReading), encoding: .utf8) ?? ""
        let stderr = String(data: ProcessPipe.readToEnd(err.fileHandleForReading), encoding: .utf8) ?? ""
        process.waitUntilExit()
        appendLog("legendary \(arguments.joined(separator: " ")) exit=\(process.terminationStatus)")
        return (process.terminationStatus, stdout, stderr)
    }

    private func runStreaming(_ arguments: [String], onLine: @escaping (String) -> Void) throws -> Int32 {
        guard isBinaryInstalled() else { throw LegendaryError.binaryMissing }
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = arguments
        process.environment = processEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        lock.lock()
        installProcess = process
        lock.unlock()
        let handle = pipe.fileHandleForReading
        var leftover = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            leftover.append(chunk)
            while let newline = leftover.firstIndex(of: 0x0A) {
                let lineData = leftover.subdata(in: leftover.startIndex..<newline)
                leftover.removeSubrange(leftover.startIndex...newline)
                if let line = String(data: lineData, encoding: .utf8) {
                    appendLog(line)
                    onLine(line)
                }
            }
        }
        if !leftover.isEmpty, let line = String(data: leftover, encoding: .utf8) {
            appendLog(line)
            onLine(line)
        }
        process.waitUntilExit()
        lock.lock()
        installProcess = nil
        lock.unlock()
        return process.terminationStatus
    }

    private func spawnDetached(arguments: [String], environment: [String: String]) throws {
        guard isBinaryInstalled() else { throw LegendaryError.binaryMissing }
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = arguments
        process.environment = environment
        let logURL = PathManager.shared.logURL(for: .epic)
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let logPipe = CappedLogWriter.shared(for: logURL).makeProcessPipe()
        process.standardOutput = logPipe
        process.standardError = logPipe
        process.qualityOfService = .userInitiated
        try process.run()
        appendLog("legendary \(arguments.joined(separator: " ")) pid=\(process.processIdentifier)")
    }

    private func appendLog(_ line: String) {
        let logURL = PathManager.shared.logURL(for: .epic)
        try? fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        CappedLogWriter.shared(for: logURL).append(line: "Vermut: " + line)
    }

    private func cleanError(_ stderr: String, stdout: String, fallback: String) -> String {
        let combined = (stderr + "\n" + stdout)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let last = combined.last(where: { $0.lowercased().contains("error") || $0.lowercased().contains("fail") }) {
            return last
        }
        return combined.last ?? fallback
    }
}
