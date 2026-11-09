import XCTest
@testable import CaskLauncherCore

final class CompatReportLogTests: XCTestCase {
    func testLastLinesKeepsTheTail() {
        let lines = (1...80).map { "line-\($0)" }
        let tail = CompatReportLog.lastLines(lines, count: 50)
        XCTAssertEqual(tail.count, 50)
        XCTAssertEqual(tail.first, "line-31")
        XCTAssertEqual(tail.last, "line-80")
        XCTAssertEqual(CompatReportLog.lastLines(["a", "b"], count: 50), ["a", "b"])
    }

    func testRedactReplacesHomeDirectoryAndGenericUserPaths() {
        let home = "/Users/mario"
        let raw = """
        wine: created process /Users/mario/Library/Application Support/Vermut/bottles/steam/prefix
        also /Users/other/secret and /home/alice/.wine
        """
        let redacted = CompatReportLog.redact(raw, homeDirectory: home)
        XCTAssertFalse(redacted.contains("mario"))
        XCTAssertFalse(redacted.contains("/Users/other"))
        XCTAssertFalse(redacted.contains("/home/alice"))
        XCTAssertTrue(redacted.contains("~/Library/Application Support/Vermut/bottles/steam/prefix"))
        XCTAssertTrue(redacted.contains("/Users/[user]"))
        XCTAssertTrue(redacted.contains("/home/[user]"))
    }

    func testExcerptCapsAtFiftyRedactedLines() {
        var lines: [String] = []
        for i in 1...60 {
            lines.append("\(i) /Users/riley/path")
        }
        let excerpt = CompatReportLog.excerpt(from: lines, homeDirectory: "/Users/riley")
        let out = excerpt.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(out.count, 50)
        XCTAssertEqual(String(out.first ?? ""), "11 ~/path")
        XCTAssertFalse(excerpt.contains("riley"))
        XCTAssertFalse(excerpt.contains("1 /Users/riley"))
    }

    func testComposeNoteKeepsUserTextAndLog() {
        XCTAssertEqual(
            CompatReportLog.composeNote(userNote: "crash", logExcerpt: "wine: err"),
            "crash\n\n\(CompatReportLog.logHeader)\nwine: err"
        )
        XCTAssertEqual(
            CompatReportLog.composeNote(userNote: nil, logExcerpt: "wine: err"),
            "\(CompatReportLog.logHeader)\nwine: err"
        )
        XCTAssertEqual(CompatReportLog.composeNote(userNote: "ok", logExcerpt: nil), "ok")
        XCTAssertNil(CompatReportLog.composeNote(userNote: "  ", logExcerpt: ""))
    }

    func testFittingURLDropsOldestLogLinesAndNeverFails() {
        let longLine = String(repeating: "WINE ", count: 80)
        let lines = (1...50).map { "\($0) \(longLine)" }
        let excerpt = lines.joined(separator: "\n")
        var capturedNotes: [String?] = []
        let url = CompatReportLog.fittingURL(
            userNote: "audio glitch",
            logExcerpt: excerpt,
            maxLength: 900
        ) { note in
            capturedNotes.append(note)
            var components = URLComponents(string: "https://github.com/Contessafry/Vermut/issues/new")
            components?.queryItems = [
                URLQueryItem(name: "title", value: "[compat] Hades — broken"),
                URLQueryItem(name: "note", value: note ?? "")
            ]
            return components?.url
        }
        XCTAssertNotNil(url)
        XCTAssertLessThanOrEqual(url!.absoluteString.count, 900)
        XCTAssertTrue(capturedNotes.contains { $0?.contains("audio glitch") == true })
        if let final = url?.absoluteString {
            XCTAssertTrue(final.contains("Hades") || final.contains("compat"))
        }
    }

    func testFittingURLOmitsLogWhenEvenOneLineOverflows() {
        let huge = String(repeating: "x", count: 4000)
        let url = CompatReportLog.fittingURL(
            userNote: "note-ok",
            logExcerpt: huge,
            maxLength: 200
        ) { note in
            var components = URLComponents(string: "https://example.test/issues/new")
            var items = [URLQueryItem(name: "t", value: "ok")]
            if let note { items.append(URLQueryItem(name: "note", value: note)) }
            components?.queryItems = items
            return components?.url
        }
        XCTAssertNotNil(url)
        XCTAssertLessThanOrEqual(url!.absoluteString.count, 200)
        XCTAssertFalse(url!.absoluteString.contains(huge))
    }
}
