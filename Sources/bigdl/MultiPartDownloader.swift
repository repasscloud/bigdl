import Foundation

/// Coordinates a concurrent, multi-part download of a single URL by
/// splitting it into byte ranges, downloading each range into its own
/// `.partN` file, and concatenating the parts once all have finished.
final class MultiPartDownloader: Sendable {
    private let url: URL
    private let outputURL: URL
    private let threads: Int
    private let chunkSize: Int64?

    init(url: URL, outputURL: URL, threads: Int, chunkSize: Int64?) {
        self.url = url
        self.outputURL = outputURL
        self.threads = max(1, threads)
        self.chunkSize = chunkSize
    }

    private func partURL(for index: Int) -> URL {
        URL(fileURLWithPath: outputURL.path + ".part\(index)")
    }

    /// Returns `false` if the server doesn't support multi-part downloads
    /// (no `Accept-Ranges: bytes` and/or unknown content length), in which
    /// case the caller should fall back to a single-stream download.
    func canDownload() async throws -> Bool {
        var request = URLRequest(url: url)

        request.httpMethod = "HEAD"
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }

        guard response.statusCode < 400 else {
            throw DownloadError.serverError(response.statusCode)
        }

        let acceptsRanges =
            response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

        return acceptsRanges && response.expectedContentLength > 0
    }

    func download() async throws {
        var headRequest = URLRequest(url: url)

        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 60

        let (_, headResponse) = try await URLSession.shared.data(
            for: headRequest
        )

        guard
            let headResponse = headResponse as? HTTPURLResponse,
            headResponse.expectedContentLength > 0
        else {
            throw DownloadError.unknownContentLength
        }

        let totalBytes = headResponse.expectedContentLength

        let ranges = computePartRanges(
            totalBytes: totalBytes,
            threads: threads,
            chunkSize: chunkSize
        )

        print(
            "Downloading \(outputURL.lastPathComponent) " +
            "in \(ranges.count) part(s) using up to \(threads) thread(s)"
        )
        print("Size: \(formatBytes(totalBytes))")

        let reporter = ProgressReporter(totalBytes: totalBytes)

        for (index, range) in ranges.enumerated() {
            let existing = fileSize(at: partURL(for: index))

            await reporter.addExisting(
                min(existing, range.length)
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            let concurrency = min(threads, ranges.count)

            func startNext() {
                guard nextIndex < ranges.count else {
                    return
                }

                let index = nextIndex
                let range = ranges[index]

                nextIndex += 1

                group.addTask {
                    let part = PartDownloader(
                        url: self.url,
                        partURL: self.partURL(for: index),
                        range: range,
                        reporter: reporter
                    )

                    try await part.download()
                }
            }

            for _ in 0..<concurrency {
                startNext()
            }

            while try await group.next() != nil {
                startNext()
            }
        }

        try await combineParts(count: ranges.count)

        await reporter.printFinal()

        print()
        print(
            "Saved \(formatBytes(totalBytes)) " +
            "to \(outputURL.path)"
        )
    }

    private func combineParts(count: Int) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil
        )

        let output = try FileHandle(forWritingTo: outputURL)

        defer {
            try? output.close()
        }

        for index in 0..<count {
            let url = partURL(for: index)

            let input = try FileHandle(forReadingFrom: url)

            while true {
                let data = try input.read(upToCount: 1 << 20) ?? Data()

                if data.isEmpty {
                    break
                }

                try output.write(contentsOf: data)
            }

            try input.close()

            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Tracks aggregate progress across all concurrently downloading parts and
/// prints a single combined progress line.
actor ProgressReporter {
    private let totalBytes: Int64
    private var downloadedBytes: Int64 = 0
    private let startTime = ContinuousClock.now

    init(totalBytes: Int64) {
        self.totalBytes = totalBytes
    }

    func addExisting(_ bytes: Int64) {
        downloadedBytes += bytes
    }

    func addBytes(_ count: Int64) {
        downloadedBytes += count

        printProgress()
    }

    func printFinal() {
        printProgress()
    }

    private func printProgress() {
        let elapsed = startTime.duration(to: .now)

        let seconds =
            Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1e18

        let speed = seconds > 0
            ? Double(downloadedBytes) / seconds
            : 0

        var line = "\r\(formatBytes(downloadedBytes))"

        if totalBytes > 0 {
            let percentage =
                Double(downloadedBytes) /
                Double(totalBytes) *
                100

            line += String(
                format: " / %@  %6.2f%%",
                formatBytes(totalBytes),
                percentage
            )
        }

        line += "  \(formatBytes(Int64(speed)))/s"

        if speed > 0, downloadedBytes < totalBytes {
            let remaining = Double(totalBytes - downloadedBytes)
            let eta = remaining / speed

            line += "  ETA \(formatDuration(eta))"
        }

        print("\r\u{001B}[K\(line)", terminator: "")

        fflush(stdout)
    }
}

/// Downloads a single byte range into its own part file, resuming from
/// whatever bytes of that range are already on disk.
final class PartDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let partURL: URL
    private let range: ByteRange
    private let reporter: ProgressReporter

    private var fileHandle: FileHandle?
    private var existingInPart: Int64 = 0
    private var responseAccepted = false

    private var continuation:
        CheckedContinuation<Void, any Error>?

    init(url: URL, partURL: URL, range: ByteRange, reporter: ProgressReporter) {
        self.url = url
        self.partURL = partURL
        self.range = range
        self.reporter = reporter
    }

    func download() async throws {
        existingInPart = min(fileSize(at: partURL), range.length)

        if existingInPart >= range.length {
            // This part was already fully downloaded on a previous run.
            return
        }

        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(
                atPath: partURL.path,
                contents: nil
            )
        }

        fileHandle = try FileHandle(forWritingTo: partURL)

        try fileHandle?.seekToEnd()

        var request = URLRequest(url: url)

        request.timeoutInterval = 60 * 60

        let rangeStart = range.start + existingInPart

        request.setValue(
            "bytes=\(rangeStart)-\(range.end)",
            forHTTPHeaderField: "Range"
        )

        let configuration = URLSessionConfiguration.default

        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            self.continuation = continuation

            session
                .dataTask(with: request)
                .resume()
        }

        try fileHandle?.close()
    }

    // MARK: - Response

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler:
            @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            finish(with: DownloadError.invalidResponse)
            completionHandler(.cancel)
            return
        }

        let status = response.statusCode

        if status >= 400 {
            finish(with: DownloadError.serverError(status))
            completionHandler(.cancel)
            return
        }

        guard status == 206 else {
            finish(with: DownloadError.rangeNotSupported)
            completionHandler(.cancel)
            return
        }

        responseAccepted = true

        completionHandler(.allow)
    }

    // MARK: - Data

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard responseAccepted else {
            return
        }

        do {
            try fileHandle?.write(contentsOf: data)

            let count = Int64(data.count)

            Task {
                await reporter.addBytes(count)
            }
        } catch {
            dataTask.cancel()
            finish(with: error)
        }
    }

    // MARK: - Completion

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            finish(with: error)
            return
        }

        finish()
    }

    private func finish(with error: (any Error)? = nil) {
        guard let continuation else {
            return
        }

        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
