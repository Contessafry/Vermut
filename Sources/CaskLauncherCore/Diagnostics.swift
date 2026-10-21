import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class Diagnostics: @unchecked Sendable {
    public static let shared = Diagnostics()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func generateReport() async throws -> String {
        var report = """
        Vermut Diagnostic Report
        ==============================
        Generated: \(Date())
        
        """
        
        report += "System Information:\n"
        report += "-------------------\n"
        let processInfo = ProcessInfo.processInfo
        report += "macOS Version: \(processInfo.operatingSystemVersionString)\n"
        report += "Architecture: \(machineArchitecture())\n"
        let hasRosetta = try await SystemSetup.shared.checkRosetta()
        report += "Rosetta 2: \(hasRosetta ? "Installed" : "Not installed")\n"
        report += "\n"
        
        report += "Wine Engines:\n"
        report += "-------------\n"
        for engine in WineEngine.allCases {
            let installed = EngineManager.shared.isEngineInstalled(engine)
            report += "\(engine.displayName): \(installed ? "Installed" : "Not installed")\n"
            if installed, let layout = PathManager.shared.engineLayout(for: engine) {
                report += "  wine: \(layout.wineExecutable.path)\n"
                report += "  wineserver: \(layout.wineserverExecutable.path)\n"
                report += "  wine root: \(layout.wineRoot.path)\n"
            }
        }
        report += "\n"
        
        report += "Graphics Components:\n"
        report += "--------------------\n"
        report += "DXMT: \(PathManager.shared.dxmtLibraryPath() != nil ? "Installed" : "Not installed")\n"
        report += "DXVK: \(PathManager.shared.dxvkLibraryPath() != nil ? "Installed" : "Not installed")\n"
        let d3d = D3DMetalDetector.detect(
            customPath: (try? ConfigurationManager.shared.loadConfiguration())?.d3dMetalLibraryPath
        )
        switch d3d.presence {
        case .found(let version, let root):
            report += "D3DMetal (GPTK): Found\(version.map { " · \($0)" } ?? "") at \(root.path)\n"
        case .unsupported(let version, let root):
            report += "D3DMetal (GPTK): Unsupported\(version.map { " · \($0)" } ?? "") at \(root.path)\n"
        case .invalid(let reason):
            report += "D3DMetal (GPTK): Invalid — \(reason)\n"
        case .unavailableOnIntel:
            report += "D3DMetal (GPTK): Unavailable on Intel\n"
        case .notFound:
            report += "D3DMetal (GPTK): Not found\n"
        }
        report += "\n"
        
        report += "Store Installations:\n"
        report += "--------------------\n"
        for store in GameStore.allCases {
            let installed = WineManager.shared.isStoreInstalled(store)
            let running = WineManager.shared.isStoreRunning(store)
            report += "\(store.rawValue): \(installed ? "Installed" : "Not installed")"
            if running {
                report += " (Running)"
            }
            report += "\n"
            if store == .epic {
                report += "  Legendary: \(LegendaryManager.shared.isBinaryInstalled() ? "Installed" : "Missing")\n"
                if let account = LegendaryManager.shared.account() {
                    report += "  Epic account: \(account.displayName)\n"
                } else {
                    report += "  Epic account: signed out\n"
                }
            }
            
            if installed {
                let bottleURL = PathManager.shared.bottleURL(for: store)
                if let size = try? calculateDirectorySize(bottleURL) {
                    report += "  Bottle size: \(formatBytes(size))\n"
                }
            }
        }
        report += "\n"
        
        report += "Recent Log Snippets:\n"
        report += "--------------------\n"
        for store in GameStore.allCases {
            let logURL = PathManager.shared.logURL(for: store)
            if fileManager.fileExists(atPath: logURL.path) {
                report += "\n\(store.rawValue) log (last 20 lines):\n"
                let snap = LogTail.read(from: logURL, maxBytes: 64 * 1024, maxLines: 20)
                if snap.lines.isEmpty {
                    report += "  (empty)\n"
                } else {
                    report += redactSensitiveInfo(snap.lines.joined(separator: "\n"))
                    report += "\n"
                }
            }
        }
        
        return report
    }
    
    public func runDoctor() async -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        
        let hasRosetta = (try? await SystemSetup.shared.checkRosetta()) ?? false
        if !hasRosetta {
            issues.append(DiagnosticIssue(
                severity: .error,
                category: "System",
                message: "Rosetta 2 is not installed",
                fix: "Install Rosetta 2 through System Setup"
            ))
        }
        
        let hasAnyEngine = WineEngine.allCases.contains { EngineManager.shared.isEngineInstalled($0) }
        if !hasAnyEngine {
            issues.append(DiagnosticIssue(
                severity: .error,
                category: "Wine",
                message: "No Wine engine is installed",
                fix: "Download at least one Wine engine"
            ))
        }
        
        if PathManager.shared.dxmtLibraryPath() == nil {
            issues.append(DiagnosticIssue(
                severity: .warning,
                category: "Graphics",
                message: "DXMT is not installed",
                fix: "Download DXMT for better DirectX 10/11 performance"
            ))
        }
        
        for store in GameStore.allCases {
            if WineManager.shared.isStoreInstalled(store) {
                let bottleURL = PathManager.shared.bottleURL(for: store)
                let diskSpace = try? getDiskSpace(at: bottleURL)
                
                if let diskSpace = diskSpace, diskSpace < 5_000_000_000 {
                    issues.append(DiagnosticIssue(
                        severity: .warning,
                        category: "Storage",
                        message: "Low disk space for \(store.rawValue) bottle",
                        fix: "Free up disk space (less than 5 GB available)"
                    ))
                }
            }
        }
        
        if issues.isEmpty {
            issues.append(DiagnosticIssue(
                severity: .info,
                category: "System",
                message: "All checks passed",
                fix: nil
            ))
        }
        
        return issues
    }
    
    private func calculateDirectorySize(_ url: URL) throws -> Int64 {
        var size: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                size += Int64(attributes.fileSize ?? 0)
            }
        }
        
        return size
    }
    
    private func getDiskSpace(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfFileSystem(forPath: url.path)
        return attributes[.systemFreeSize] as? Int64 ?? 0
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func redactSensitiveInfo(_ text: String) -> String {
        var redacted = text
        
        let patterns = [
            "(/Users/[^/\\s]+)": "/Users/[REDACTED]",
            "([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,})": "[EMAIL]"
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(redacted.startIndex..., in: redacted)
                redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: replacement)
            }
        }
        
        return redacted
    }
    
    private func machineArchitecture() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #elseif os(Linux)
        var utsname = utsname()
        guard uname(&utsname) == 0 else {
            return "unknown"
        }
        return withUnsafePointer(to: &utsname.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
        #else
        return "unknown"
        #endif
    }
}

public struct DiagnosticIssue: Identifiable, Sendable {
    public let id = UUID()
    public let severity: Severity
    public let category: String
    public let message: String
    public let fix: String?
    
    public enum Severity: Sendable {
        case info
        case warning
        case error
    }
}
