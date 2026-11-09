import Foundation

/// Last bottle-log lines attached to a compatibility GitHub issue, with redaction and URL-length safety.
public enum CompatReportLog {
    public static let maxLines = 50
    /// GitHub issue-creation URLs are rejected well below typical browser limits.
    public static let githubIssueURLMaxLength = 8000
    public static let logHeader = "Log (ultime 50 righe):"

    public static func lastLines(_ lines: [String], count: Int = maxLines) -> [String] {
        guard count > 0 else { return [] }
        if lines.count <= count { return lines }
        return Array(lines.suffix(count))
    }

    /// Replaces the current home directory and other `/Users/<name>` or `/home/<name>` prefixes.
    public static func redact(_ text: String, homeDirectory: String) -> String {
        var redacted = text
        let home = normalizedPath(homeDirectory)
        if !home.isEmpty, home != "/" {
            redacted = redacted.replacingOccurrences(of: home, with: "~")
        }
        if let regex = try? NSRegularExpression(pattern: #"/(Users|home)/[^/\s"'\\]+"#) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "/$1/[user]")
        }
        return redacted
    }

    public static func excerpt(
        from lines: [String],
        homeDirectory: String,
        maxLines: Int = maxLines
    ) -> String {
        lastLines(lines, count: maxLines)
            .map { redact($0, homeDirectory: homeDirectory) }
            .joined(separator: "\n")
    }

    public static func composeNote(userNote: String?, logExcerpt: String?) -> String? {
        let user = userNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let log = logExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if user.isEmpty, log.isEmpty { return nil }
        if log.isEmpty { return user }
        if user.isEmpty { return "\(logHeader)\n\(log)" }
        return "\(user)\n\n\(logHeader)\n\(log)"
    }

    /// Bounded read of the store bottle log. Never throws; missing files yield an empty string.
    public static func loadExcerpt(
        for store: GameStore,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        let url = PathManager.shared.logURL(for: store)
        CappedLogWriter.shared(for: url).flush()
        let snap = LogTail.read(from: url, maxBytes: 64 * 1024, maxLines: maxLines)
        return excerpt(from: snap.lines, homeDirectory: homeDirectory)
    }

    /// Drops oldest log lines until `makeURL` is at most `maxLength` characters. Always returns a URL if `makeURL` can.
    public static func fittingURL(
        userNote: String?,
        logExcerpt: String?,
        maxLength: Int = githubIssueURLMaxLength,
        makeURL: (String?) -> URL?
    ) -> URL? {
        var lines = lastLines(
            (logExcerpt ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        )
        if lines.count == 1, lines[0].isEmpty {
            lines = []
        }

        while true {
            let excerpt = lines.isEmpty ? nil : lines.joined(separator: "\n")
            let note = composeNote(userNote: userNote, logExcerpt: excerpt)
            if let url = makeURL(note), url.absoluteString.count <= maxLength {
                return url
            }
            if lines.isEmpty {
                if let url = makeURL(userNote), url.absoluteString.count <= maxLength {
                    return url
                }
                return makeURL(nil)
            }
            lines.removeFirst()
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
