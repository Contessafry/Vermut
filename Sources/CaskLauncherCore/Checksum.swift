import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum Checksum {
    static func sha256Hex(ofFile url: URL) throws -> String {
        #if canImport(CryptoKit)
        return try sha256WithCryptoKit(url)
        #else
        return try sha256WithProcess(url)
        #endif
    }

    static func verify(file url: URL, expectedHex: String) throws {
        let actual = try sha256Hex(ofFile: url)
        if actual.lowercased() != expectedHex.lowercased() {
            throw DownloadError.checksumMismatch(expected: expectedHex.lowercased(), actual: actual)
        }
    }

    #if canImport(CryptoKit)
    private static func sha256WithCryptoKit(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    #endif

    private static func sha256WithProcess(_ url: URL) throws -> String {
        let process = Process()
        let sha256sum = URL(fileURLWithPath: "/usr/bin/sha256sum")
        let shasum = URL(fileURLWithPath: "/usr/bin/shasum")
        if FileManager.default.fileExists(atPath: sha256sum.path) {
            process.executableURL = sha256sum
            process.arguments = [url.path]
        } else {
            process.executableURL = shasum
            process.arguments = ["-a", "256", url.path]
        }

        process.standardError = FileHandle.nullDevice
        let data = try ProcessPipe.runReadingStdout(process)
        guard process.terminationStatus == 0 else {
            throw DownloadError.checksumMismatch(expected: "unknown", actual: "hash-failed")
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        let hash = output.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard hash.count == 64 else {
            throw DownloadError.checksumMismatch(expected: "unknown", actual: output)
        }
        return hash.lowercased()
    }
}
