import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ReleaseInfo: Codable, Sendable, Equatable {
    public let tagName: String
    public let htmlUrl: String
    public let name: String?
    public let body: String?
    public let prerelease: Bool
    public let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case prerelease
        case draft
    }

    public init(
        tagName: String,
        htmlUrl: String,
        name: String? = nil,
        body: String? = nil,
        prerelease: Bool = false,
        draft: Bool = false
    ) {
        self.tagName = tagName
        self.htmlUrl = htmlUrl
        self.name = name
        self.body = body
        self.prerelease = prerelease
        self.draft = draft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
    }
}

public enum UpdateCheckResult: Sendable, Equatable {
    case upToDate
    case updateAvailable(version: String, url: String, releaseNotes: String?, isPrerelease: Bool)
    case networkError
}

public final class UpdateChecker: @unchecked Sendable {
    public static let shared = UpdateChecker()

    private let lastCheckKey = "vermut.lastUpdateCheck"
    private let dismissedVersionKey = "vermut.dismissedUpdateVersion"
    private let checkInterval: TimeInterval = 24 * 60 * 60

    /// Injected for unit tests.
    var session: URLSession = .shared
    var releasesAPIBase: String = "https://api.github.com/repos/\(VermutProject.githubOwner)/\(VermutProject.githubRepository)"

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

    public func checkForUpdate(
        currentVersion: String,
        channel: UpdateChannel = .stable,
        force: Bool = false
    ) async -> UpdateCheckResult {
        if !force && !shouldCheckForUpdate() {
            return .upToDate
        }

        lastCheckDate = Date()

        do {
            let releases: [ReleaseInfo]
            switch channel {
            case .stable:
                if let latest = try await fetchLatestStable() {
                    releases = [latest]
                } else {
                    return .networkError
                }
            case .beta:
                releases = try await fetchAllReleases()
            }

            guard let candidate = Self.selectCandidate(
                from: releases,
                channel: channel,
                currentVersion: currentVersion
            ) else {
                return .upToDate
            }

            if let dismissed = dismissedVersion,
               SemVer.compare(dismissed, candidate.tagName) == .orderedSame {
                return .upToDate
            }

            let isPre = candidate.prerelease || SemVer.tagIsPrerelease(candidate.tagName)
            return .updateAvailable(
                version: candidate.tagName,
                url: candidate.htmlUrl,
                releaseNotes: candidate.body,
                isPrerelease: isPre
            )
        } catch {
            return .networkError
        }
    }

    /// Picks the highest eligible release for the channel that is strictly newer than `currentVersion`.
    /// Stable never offers a downgrade (e.g. leaving Beta on `1.2.0-beta.1` will not suggest `1.1.0`).
    public static func selectCandidate(
        from releases: [ReleaseInfo],
        channel: UpdateChannel,
        currentVersion: String
    ) -> ReleaseInfo? {
        let eligible = releases.filter { release in
            guard !release.draft else { return false }
            guard SemVer.parse(release.tagName) != nil else { return false }
            switch channel {
            case .stable:
                return !release.prerelease && !SemVer.tagIsPrerelease(release.tagName)
            case .beta:
                return true
            }
        }

        guard let best = eligible.max(by: {
            SemVer.compare($0.tagName, $1.tagName) == .orderedAscending
        }) else {
            return nil
        }

        // Only offer upgrades — never a lower (or equal) version than what is installed.
        if SemVer.compare(best.tagName, currentVersion) == .orderedDescending {
            return best
        }
        return nil
    }

    public func dismissUpdate(version: String) {
        dismissedVersion = version
    }

    public func clearDismissed() {
        dismissedVersion = nil
    }

    private func fetchLatestStable() async throws -> ReleaseInfo? {
        guard let url = URL(string: "\(releasesAPIBase)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    private func fetchAllReleases(perPage: Int = 30) async throws -> [ReleaseInfo] {
        guard let url = URL(string: "\(releasesAPIBase)/releases?per_page=\(perPage)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vermut/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ReleaseInfo].self, from: data)
    }
}
