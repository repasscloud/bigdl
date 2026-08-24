import Foundation

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()

    formatter.countStyle = .binary

    return formatter.string(
        fromByteCount: bytes
    )
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)

    let hours = total / 3600
    let minutes = total % 3600 / 60
    let secs = total % 60

    if hours > 0 {
        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            secs
        )
    }

    return String(
        format: "%02d:%02d",
        minutes,
        secs
    )
}

func fileSize(at url: URL) -> Int64 {
    guard
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ),
        let size = attributes[.size] as? NSNumber
    else {
        return 0
    }

    return size.int64Value
}

/// Parses a human-friendly byte size like "10MB", "512KB", "1GiB", or a
/// plain byte count like "1048576" into a byte count.
func parseByteSize(_ value: String) -> Int64? {
    let trimmed = value.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
        return nil
    }

    let digitsEndIndex = trimmed.firstIndex {
        !($0.isNumber || $0 == ".")
    } ?? trimmed.endIndex

    let numberPart = trimmed[trimmed.startIndex..<digitsEndIndex]
    let unitPart = trimmed[digitsEndIndex...]
        .trimmingCharacters(in: .whitespaces)
        .uppercased()

    guard let number = Double(numberPart) else {
        return nil
    }

    let multiplier: Double

    switch unitPart {
    case "", "B":
        multiplier = 1

    case "K", "KB":
        multiplier = 1_000

    case "KI", "KIB":
        multiplier = 1_024

    case "M", "MB":
        multiplier = 1_000_000

    case "MI", "MIB":
        multiplier = 1_048_576

    case "G", "GB":
        multiplier = 1_000_000_000

    case "GI", "GIB":
        multiplier = 1_073_741_824

    default:
        return nil
    }

    return Int64(number * multiplier)
}

struct ByteRange: Sendable {
    let start: Int64
    let end: Int64

    var length: Int64 {
        end - start + 1
    }
}

/// Splits `totalBytes` into contiguous, inclusive byte ranges.
///
/// - If `chunkSize` is provided, each part is `chunkSize` bytes (the last
///   part may be shorter).
/// - Otherwise, `totalBytes` is split evenly across `threads` parts.
func computePartRanges(
    totalBytes: Int64,
    threads: Int,
    chunkSize: Int64?
) -> [ByteRange] {
    guard totalBytes > 0 else {
        return []
    }

    let partSize: Int64

    if let chunkSize, chunkSize > 0 {
        partSize = chunkSize
    } else {
        let threads = max(1, Int64(threads))
        partSize = (totalBytes + threads - 1) / threads
    }

    var ranges: [ByteRange] = []
    var offset: Int64 = 0

    while offset < totalBytes {
        let end = min(offset + partSize - 1, totalBytes - 1)

        ranges.append(ByteRange(start: offset, end: end))

        offset = end + 1
    }

    return ranges
}
