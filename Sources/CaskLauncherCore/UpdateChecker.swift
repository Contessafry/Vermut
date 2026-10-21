import Foundation

public struct ReleaseInfo: Codable, Sendable {
    public let tagName: String
    public let htmlUrl: String
    public let name: String?
    public let body: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
    }
}

public enum UpdateCheckResult: Sendable {
    case upToDate
    case updateAvailable(version: String, url: String, releaseNotes: String?)
    case networkError
}

public final class UpdateChecker: @unchecked Sendable {
    public static let shared = UpdateChecker()
    
    private let lastCheckKey = "vermut.lastUpdateCheck"
    private let dismissedVersionKey = "vermut.dismissedUpdateVersion"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    
    private init() {}
    
    public var lastCheckDate: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: lastCheckKey) as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastCheckKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastCheckKey)
            }
        }
    }
    
    public var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: dismissedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedVersionKey) }
    }
    
    public func shouldCheckForUpdate() -> Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }
    
    public func checkForUpdate(currentVersion: String, force: Bool = false) async -> UpdateCheckResult {
        if !force && !shouldCheckForUpdate() {
            return .upToDate
        }
        
        lastCheckDate = Date()
        
        let urlString = "https://api.github.com/repos/\(VermutProject.githubOwner)/\(VermutProject.githubRepository)/releases/latest"
        guard let url = URL(string: urlString) else {
            return .networkError
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .networkError
            }
            
            let decoder = JSONDecoder()
            let release = try decoder.decode(ReleaseInfo.self, from: data)
            
            let latestVersion = normalizeVersion(release.tagName)
            let current = normalizeVersion(currentVersion)
            
            if compareVersions(latestVersion, current) == .orderedDescending {
                if let dismissed = dismissedVersion, normalizeVersion(dismissed) == latestVersion {
                    return .upToDate
                }
                return .updateAvailable(
                    version: release.tagName,
                    url: release.htmlUrl,
                    releaseNotes: release.body
                )
            }
            
            return .upToDate
        } catch {
            return .networkError
        }
    }
    
    public func dismissUpdate(version: String) {
        dismissedVersion = version
    }
    
    public func clearDismissed() {
        dismissedVersion = nil
    }
    
    private func normalizeVersion(_ version: String) -> String {
        var v = version
        if v.hasPrefix("v") {
            v = String(v.dropFirst())
        }
        return v
    }
    
    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(lhsComponents.count, rhsComponents.count)
        
        for i in 0..<maxCount {
            let l = i < lhsComponents.count ? lhsComponents[i] : 0
            let r = i < rhsComponents.count ? rhsComponents[i] : 0
            
            if l < r {
                return .orderedAscending
            } else if l > r {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}
