import Foundation

public final class SystemSetup: @unchecked Sendable {
    public static let shared = SystemSetup()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func checkRosetta() async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["oahd"]
        
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func installRosetta() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--install-rosetta", "--agree-to-license"]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw SetupError.rosettaInstallFailed
        }
    }
    
    public func checkWineInstalled() -> Bool {
        EngineManager.shared.isEngineInstalled(WineEngine.defaultEngine)
    }
    
    public func checkDXMTInstalled() -> Bool {
        _ = DXMTVersionManager.shared.migrateLegacyFlatInstallIfNeeded()
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
        let gptk1Path = "/usr/local/lib/libd3dshared.dylib"
        let gptk2Path = "/opt/homebrew/lib/libd3dshared.dylib"
        
        return fileManager.fileExists(atPath: gptk1Path) || 
               fileManager.fileExists(atPath: gptk2Path)
    }
    
    public func downloadDefaultEngine(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await EngineManager.shared.downloadEngine(.grappleWine, progress: progress)
    }
    
    public func downloadDXMT(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await EngineManager.shared.downloadDXMT(progress: progress)
    }
    
}

public enum SetupError: LocalizedError {
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
