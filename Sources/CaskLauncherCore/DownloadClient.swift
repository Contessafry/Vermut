import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum DownloadClient {
    static func download(
        from url: URL,
        to destination: URL,
        expectedSHA256: String? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if UninstallPersistenceGate.writesSuppressed {
            throw CancellationError()
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if cachedFileIsValid(at: destination, expectedSHA256: expectedSHA256) {
            progress(1.0)
            return
        }

        let stagingURL = URL(fileURLWithPath: destination.path + ".partial")
        let downloader = FileDownloadTask()
        try await downloader.download(from: url, to: stagingURL, progress: progress)

        if let expectedSHA256, !expectedSHA256.isEmpty {
            do {
                try Checksum.verify(file: stagingURL, expectedHex: expectedSHA256)
            } catch {
                try? FileManager.default.removeItem(at: stagingURL)
                throw error
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: stagingURL, to: destination)
    }

    /// A cache hit requires the file to exist; if a SHA-256 is provided it must match.
    static func cachedFileIsValid(at url: URL, expectedSHA256: String?) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let expectedSHA256, !expectedSHA256.isEmpty else { return true }
        return (try? Checksum.sha256Hex(ofFile: url))?.lowercased() == expectedSHA256.lowercased()
    }
}

public enum DownloadError: LocalizedError, Sendable {
    case invalidURL
    case failed
    case httpFailure(Int)
    case network(String)
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .failed:
            return "Download failed"
        case .httpFailure(let code):
            return "Download failed (HTTP \(code)). The file may have moved; check your network and retry."
        case .network(let message):
            return "Download failed: \(message)"
        case .checksumMismatch:
            return "Downloaded file failed SHA-256 verification. Delete the cache and retry."
        }
    }
}

/// Streams a file to disk with a URLSession download task and reports progress
/// from `urlSession(_:downloadTask:didWriteData:...)`.
final class FileDownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var finishError: Error?
    private var lastReportedProgress = -1.0

    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.destination = destination
        self.progressHandler = progress
        progress(0)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Vermut/1.0"]
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        reportProgress(value)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        if !(200..<300).contains(status) {
            finishError = DownloadError.httpFailure(status)
            return
        }

        guard let destination else {
            finishError = DownloadError.failed
            return
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try fileManager.moveItem(at: location, to: destination)
            } catch {
                try fileManager.copyItem(at: location, to: destination)
            }
        } catch {
            finishError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            resume(.failure(DownloadError.network(error.localizedDescription)))
            return
        }
        if let finishError {
            resume(.failure(finishError))
            return
        }
        reportProgress(1.0)
        resume(.success(()))
    }

    private func reportProgress(_ value: Double) {
        lock.lock()
        let shouldReport = value >= 1.0 || value - lastReportedProgress >= 0.01
        if shouldReport {
            lastReportedProgress = value
        }
        let handler = progressHandler
        lock.unlock()
        if shouldReport {
            handler?(value)
        }
    }

    private func resume(_ result: Result<Void, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }
}
