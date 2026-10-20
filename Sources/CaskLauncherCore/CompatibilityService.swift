import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class CompatibilityService: @unchecked Sendable {
    public static let shared = CompatibilityService()
    
    private let decoder = JSONDecoder()
    
    private static let promptEnabledKey = "vermut.compat.promptEnabled"
    
    private init() {}
    
    public var isPromptEnabled: Bool {
        get {
            if !UserDefaults.standard.bool(forKey: Self.promptEnabledKey + ".set") {
                UserDefaults.standard.set(true, forKey: Self.promptEnabledKey)
                UserDefaults.standard.set(true, forKey: Self.promptEnabledKey + ".set")
            }
            return UserDefaults.standard.bool(forKey: Self.promptEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.promptEnabledKey)
            UserDefaults.standard.set(true, forKey: Self.promptEnabledKey + ".set")
        }
    }
    
    public func generateGitHubIssueURL(report: CompatibilityReport) -> URL? {
        var components = URLComponents(string: "https://github.com/Contessafry/Vermut/issues/new")
        
        let engineDisplay = userFacingEngineName(report.engine)
        let title = "[compat] \(report.gameName ?? report.gameId) — \(report.result)"
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "template", value: "compatibility-report.yml"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "store", value: report.store),
            URLQueryItem(name: "gameId", value: report.gameId),
            URLQueryItem(name: "gameName", value: report.gameName ?? ""),
            URLQueryItem(name: "vermutVersion", value: report.vermutVersion),
            URLQueryItem(name: "engine", value: engineDisplay),
            URLQueryItem(name: "graphics", value: report.graphics),
            URLQueryItem(name: "macOS", value: report.macOS),
            URLQueryItem(name: "chip", value: report.chip),
            URLQueryItem(name: "playMinutes", value: "\(report.playMinutes)"),
            URLQueryItem(name: "result", value: report.result),
        ]
        
        if let note = report.note, !note.isEmpty {
            queryItems.append(URLQueryItem(name: "note", value: note))
        }
        
        if report.autoDetectedCrash == true {
            queryItems.append(URLQueryItem(name: "autoDetectedCrash", value: "yes"))
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    private func userFacingEngineName(_ engineId: String) -> String {
        switch engineId {
        case "grapple-wine": return "vermut-wine"
        case "staging": return "staging"
        case "devel": return "devel"
        default: return engineId
        }
    }
    
    public func fetchCompatibilityData() async throws -> CompatibilityData {
        // Debug override for QA (works in release builds too)
        if let overridePath = UserDefaults.standard.string(forKey: "vermut.compat.debugJsonPath") {
            let url: URL
            if overridePath.hasPrefix("file://") {
                guard let fileUrl = URL(string: overridePath) else {
                    print("Invalid file:// URL: \(overridePath)")
                    throw CompatibilityError.invalidURL
                }
                url = fileUrl
            } else {
                url = URL(fileURLWithPath: overridePath)
            }
            
            do {
                let data = try Data(contentsOf: url)
                let decoded = try decoder.decode(CompatibilityData.self, from: data)
                print("Loaded compatibility data from debug override: \(overridePath)")
                return decoded
            } catch {
                print("Failed to load/decode debug compatibility JSON from \(overridePath): \(error)")
                throw error
            }
        }
        
        let urlString = "https://raw.githubusercontent.com/Contessafry/Vermut/main/compat/compatibility.json"
        guard let url = URL(string: urlString) else {
            throw CompatibilityError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Vermut/\(VermutProject.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CompatibilityError.invalidResponse
        }
        
        return try decoder.decode(CompatibilityData.self, from: data)
    }
    
    public func triggerDebugFeedback(session: GameSession, autoDetectedCrash: Bool) {
        // Debug helper to trigger the feedback banner (works in release builds)
        NotificationCenter.default.post(
            name: NSNotification.Name("VermutDebugTriggerCompatFeedback"),
            object: nil,
            userInfo: ["session": session, "crash": autoDetectedCrash]
        )
    }
}

public enum CompatibilityError: LocalizedError {
    case invalidURL
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from GitHub"
        }
    }
}
