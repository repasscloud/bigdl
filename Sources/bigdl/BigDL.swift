import Foundation

@main
struct BigDL {
    static let version: String = "0.2.0"

    static let defaultThreads = 4

    static let copyrightNotice: String = """
    Copyright (C) 2026 Danijel-James Wynyard
    License GPLv3+: GNU GPL version 3 or later <https://www.gnu.org/licenses/gpl-3.0.html>
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.
    """

    static let help: String = """
    bigdl \(version)
    \(copyrightNotice)

    Usage:
      bigdl <url> [output] [options]
      bigdl --help
      bigdl --version

    Arguments:
      url                   URL of the file to download
      output                Optional output filename

    Options:
      -h, --help            Show this help
      -v, --version         Show version
      --async               Download in multiple parts concurrently
                             (implied by --threads or --chunk-size)
      --threads N           Max concurrent parts (default: \(defaultThreads));
                             implies --async
      --chunk-size SIZE     Size of each part, e.g. 10MB, 512KB, 1GiB
                             (default: total size / threads); implies
                             --async

    Examples:
      bigdl https://testfile.to/dl/1gb
      bigdl https://testfile.to/dl/1gb download.bin
      bigdl https://testfile.to/dl/1gb --threads 8
      bigdl https://testfile.to/dl/1gb --chunk-size 25MB
      bigdl https://testfile.to/dl/1gb --chunk-size 25MB --threads 8
    """

    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())

            guard let firstArgument = arguments.first else {
                print(help)
                return
            }

            switch firstArgument {
            case "-h", "--help":
                print(help)
                return

            case "-v", "--version":
                print("bigdl \(version)")
                print(copyrightNotice)
                return

            default:
                break
            }

            let options = try parseOptions(arguments)

            guard let url = URL(string: options.urlString) else {
                throw DownloadError.invalidURL
            }

            let outputURL: URL

            if let output = options.output {
                outputURL = URL(fileURLWithPath: output)
            } else {
                outputURL = URL(
                    fileURLWithPath: url.lastPathComponent.isEmpty
                        ? "download.bin"
                        : url.lastPathComponent
                )
            }

            if options.async {
                let multiPart = MultiPartDownloader(
                    url: url,
                    outputURL: outputURL,
                    threads: options.threads,
                    chunkSize: options.chunkSize
                )

                if try await multiPart.canDownload() {
                    try await multiPart.download()
                    return
                }

                print(
                    "warning: server does not support multi-part " +
                    "downloads for this URL, falling back to a single " +
                    "connection"
                )
            }

            let downloader = Downloader(
                url: url,
                outputURL: outputURL
            )

            try await downloader.download()

        } catch {
            fputs("error: \(describe(error))\n", stderr)
            exit(1)
        }
    }

    private static func describe(_ error: any Error) -> String {
        if let downloadError = error as? DownloadError {
            return downloadError.description
        }

        if let optionsError = error as? OptionsError {
            return optionsError.description
        }

        return (error as NSError).localizedDescription
    }

    struct Options {
        var urlString: String
        var output: String?
        var async: Bool = false
        var threads: Int = defaultThreads
        var chunkSize: Int64?
    }

    enum OptionsError: Error, CustomStringConvertible {
        case missingValue(String)
        case invalidThreads(String)
        case invalidChunkSize(String)
        case missingURL

        var description: String {
            switch self {
            case .missingValue(let flag):
                "Missing value for \(flag)"

            case .invalidThreads(let value):
                "Invalid value for --threads: \(value)"

            case .invalidChunkSize(let value):
                "Invalid value for --chunk-size: \(value)"

            case .missingURL:
                "Missing URL"
            }
        }
    }

    static func parseOptions(_ arguments: [String]) throws -> Options {
        var positional: [String] = []
        var async = false
        var threads = defaultThreads
        var chunkSize: Int64?

        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--async":
                async = true
                index += 1

            case "--threads":
                guard index + 1 < arguments.count else {
                    throw OptionsError.missingValue("--threads")
                }

                let value = arguments[index + 1]

                guard let parsed = Int(value), parsed > 0 else {
                    throw OptionsError.invalidThreads(value)
                }

                threads = parsed
                async = true
                index += 2

            case "--chunk-size":
                guard index + 1 < arguments.count else {
                    throw OptionsError.missingValue("--chunk-size")
                }

                let value = arguments[index + 1]

                guard let parsed = parseByteSize(value), parsed > 0 else {
                    throw OptionsError.invalidChunkSize(value)
                }

                chunkSize = parsed
                async = true
                index += 2

            default:
                positional.append(argument)
                index += 1
            }
        }

        guard let urlString = positional.first else {
            throw OptionsError.missingURL
        }

        let output = positional.count >= 2 ? positional[1] : nil

        return Options(
            urlString: urlString,
            output: output,
            async: async,
            threads: threads,
            chunkSize: chunkSize
        )
    }
}
