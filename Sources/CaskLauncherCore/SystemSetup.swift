import Foundation

public final class SystemSetup: @unchecked Sendable {
    public static let shared = SystemSetup()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func checkRosetta(
        isAppleSilicon: Bool = HostArchitecture.isAppleSilicon,
        runner: any RosettaCommandRunning = ProcessRosettaCommandRunner()
    ) async throws -> Bool {
        let silicon = isAppleSilicon
        let probe = runner
        return await Task.detached(priority: .utility) {
            RosettaCheck.evaluate(isAppleSilicon: silicon, runner: probe).isUsable
        }.value
    }
    
    public func installRosetta() async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--install-rosetta", "--agree-to-license"]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SetupError.rosettaInstallFailed
            }
        }.value
    }
    
    public func checkWineInstalled() -> Bool {
        EngineManager.shared.isEngineInstalled(WineEngine.defaultEngine)
    }
    
    public func checkDXMTInstalled() -> Bool {
        _ = DXMTVersionManager.shared.ensureMigrated()
        if PathManager.shared.isDXMTInstalled() {
            return true
        }
        if let layout = PathManager.shared.engineLayout(for: .grappleWine),
           layout.bundledDXMTOverlay()?.hasD3D11 == true {
            return true
        }
        return false
    }
    
    public func checkD3DMetalInstalled() -> Bool {
        let custom = (try? ConfigurationManager.shared.loadConfiguration())?.d3dMetalLibraryPath
        return D3DMetalDetector.detect(customPath: custom).presence.isUsable
    }
    
    public func downloadDefaultEngine(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await EngineManager.shared.downloadEngine(.grappleWine, progress: progress)
    }
    
    public func downloadDXMT(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await EngineManager.shared.downloadDXMT(progress: progress)
    }
    
}

public enum SetupError: LocalizedError, Sendable {
    case rosettaInstallFailed
    case invalidURL
    case downloadFailed
    case extractionFailed
    case checksumMismatch
    
    public var errorDescription: String? {
        switch self {
        case .rosettaInstallFailed:
            return "Failed to install Rosetta 2"
        case .invalidURL:
            return "Invalid download URL"
        case .downloadFailed:
            return "Download failed"
        case .extractionFailed:
            return "Failed to extract archive"
        case .checksumMismatch:
            return "Checksum verification failed"
        }
    }
}
