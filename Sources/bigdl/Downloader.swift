import Foundation

enum DownloadError: Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case rangeNotSupported
    case unexpectedStatus(Int)
    case unknownContentLength

    var description: String {
        switch self {
        case .invalidURL:
            "Invalid URL"

        case .invalidResponse:
            "Server returned an invalid HTTP response"

        case .serverError(let status):
            "Server returned HTTP \(status)"

        case .rangeNotSupported:
            "The server does not support resuming this download"

        case .unexpectedStatus(let status):
            "Unexpected HTTP status \(status)"

        case .unknownContentLength:
            "Server did not report a content length"
        }
    }
}

final class Downloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let outputURL: URL

    private var partURL: URL {
        URL(fileURLWithPath: outputURL.path + ".part")
    }

    private var fileHandle: FileHandle?

    private var existingBytes: Int64 = 0
    private var downloadedBytes: Int64 = 0
    private var totalBytes: Int64?

    private var startTime = ContinuousClock.now

    private var continuation:
        CheckedContinuation<Void, any Error>?

    private var responseAccepted = false

    init(url: URL, outputURL: URL) {
        self.url = url
        self.outputURL = outputURL
    }

    func download() async throws {
        existingBytes = fileSize(at: partURL)
        downloadedBytes = existingBytes

        if existingBytes > 0 {
            print(
                "Resuming \(outputURL.lastPathComponent) " +
                "from \(formatBytes(existingBytes))"
            )
        } else {
            print("Downloading \(outputURL.lastPathComponent)")
        }

        createPartFileIfNecessary()

        fileHandle = try FileHandle(
            forWritingTo: partURL
        )

        try fileHandle?.seekToEnd()

        var request = URLRequest(url: url)

        request.timeoutInterval = 60 * 60

        if existingBytes > 0 {
            request.setValue(
                "bytes=\(existingBytes)-",
                forHTTPHeaderField: "Range"
            )
        }

        let configuration = URLSessionConfiguration.default

        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )

        startTime = .now

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in

            self.continuation = continuation

            session
                .dataTask(with: request)
                .resume()
        }

        try fileHandle?.close()

        if FileManager.default.fileExists(
            atPath: outputURL.path
        ) {
            try FileManager.default.removeItem(
                at: outputURL
            )
        }

        try FileManager.default.moveItem(
            at: partURL,
            to: outputURL
        )

        print()
        print(
            "Saved \(formatBytes(downloadedBytes)) " +
            "to \(outputURL.path)"
        )
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

        if existingBytes > 0 {
            guard status == 206 else {
                finish(with: DownloadError.rangeNotSupported)
                completionHandler(.cancel)
                return
            }

            totalBytes = parseTotalSize(
                fromContentRange: response.value(
                    forHTTPHeaderField: "Content-Range"
                )
            )
        } else {
            guard status == 200 || status == 206 else {
                finish(with: DownloadError.unexpectedStatus(status))
                completionHandler(.cancel)
                return
            }

            if response.expectedContentLength > 0 {
                totalBytes = response.expectedContentLength
            }
        }

        responseAccepted = true

        if let totalBytes {
            print("Size: \(formatBytes(totalBytes))")
        }

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

            downloadedBytes += Int64(data.count)

            printProgress()
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

    // MARK: - Progress

    private func printProgress() {
        let elapsed = startTime.duration(to: .now)

        let seconds =
            Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1e18

        let downloadedThisRun =
            downloadedBytes - existingBytes

        let speed = seconds > 0
            ? Double(downloadedThisRun) / seconds
            : 0

        var line =
            "\r\(formatBytes(downloadedBytes))"

        if let totalBytes, totalBytes > 0 {
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

        line +=
            "  \(formatBytes(Int64(speed)))/s"

        if
            let totalBytes,
            speed > 0,
            downloadedBytes < totalBytes
        {
            let remaining =
                Double(totalBytes - downloadedBytes)

            let eta = remaining / speed

            line +=
                "  ETA \(formatDuration(eta))"
        }

        print(
            "\r\u{001B}[K\(line)",
            terminator: ""
        )

        fflush(stdout)
    }

    // MARK: - Helpers

    private func createPartFileIfNecessary() {
        if !FileManager.default.fileExists(
            atPath: partURL.path
        ) {
            FileManager.default.createFile(
                atPath: partURL.path,
                contents: nil
            )
        }
    }

    private func parseTotalSize(
        fromContentRange value: String?
    ) -> Int64? {
        guard let value else {
            return nil
        }

        // Example:
        //
        // bytes 28196412729-45999999999/46000000000

        guard
            let slash = value.lastIndex(of: "/"),
            slash < value.endIndex
        else {
            return nil
        }

        let total =
            value[value.index(after: slash)...]

        return Int64(total)
    }

    private func finish(
        with error: (any Error)? = nil
    ) {
        guard let continuation else {
            return
        }

        self.continuation = nil

        if let error {
            continuation.resume(
                throwing: error
            )
        } else {
            continuation.resume()
        }
    }
}
