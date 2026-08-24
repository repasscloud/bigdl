import Testing
@testable import bigdl

@Test func parsesPlainByteCount() async throws {
    #expect(parseByteSize("1048576") == 1_048_576)
}

@Test func parsesDecimalUnits() async throws {
    #expect(parseByteSize("10MB") == 10_000_000)
    #expect(parseByteSize("512KB") == 512_000)
    #expect(parseByteSize("2GB") == 2_000_000_000)
}

@Test func parsesBinaryUnits() async throws {
    #expect(parseByteSize("10MiB") == 10_485_760)
    #expect(parseByteSize("1GiB") == 1_073_741_824)
}

@Test func parsesFractionalValues() async throws {
    #expect(parseByteSize("1.5MB") == 1_500_000)
}

@Test func rejectsInvalidSizes() async throws {
    #expect(parseByteSize("") == nil)
    #expect(parseByteSize("abc") == nil)
    #expect(parseByteSize("10XB") == nil)
}

@Test func splitsEvenlyByThreadCountWhenNoChunkSize() async throws {
    let ranges = computePartRanges(
        totalBytes: 1000,
        threads: 4,
        chunkSize: nil
    )

    #expect(ranges.count == 4)
    #expect(ranges.first?.start == 0)
    #expect(ranges.last?.end == 999)

    let total = ranges.reduce(0) { $0 + $1.length }
    #expect(total == 1000)
}

@Test func splitsByChunkSizeWhenProvided() async throws {
    let ranges = computePartRanges(
        totalBytes: 1000,
        threads: 4,
        chunkSize: 300
    )

    #expect(ranges.count == 4)
    #expect(ranges[0].length == 300)
    #expect(ranges[1].length == 300)
    #expect(ranges[2].length == 300)
    #expect(ranges[3].length == 100)
    #expect(ranges.last?.end == 999)
}

@Test func returnsNoRangesForZeroBytes() async throws {
    let ranges = computePartRanges(
        totalBytes: 0,
        threads: 4,
        chunkSize: nil
    )

    #expect(ranges.isEmpty)
}

@Test func parsesAsyncFlagsFromArguments() async throws {
    let options = try BigDL.parseOptions([
        "https://example.com/file.bin",
        "out.bin",
        "--async",
        "--threads", "8",
        "--chunk-size", "10MB",
    ])

    #expect(options.urlString == "https://example.com/file.bin")
    #expect(options.output == "out.bin")
    #expect(options.async == true)
    #expect(options.threads == 8)
    #expect(options.chunkSize == 10_000_000)
}

@Test func defaultsThreadsWhenAsyncWithoutThreads() async throws {
    let options = try BigDL.parseOptions([
        "https://example.com/file.bin",
        "--async",
    ])

    #expect(options.async == true)
    #expect(options.threads == BigDL.defaultThreads)
    #expect(options.chunkSize == nil)
}

@Test func threadsImpliesAsync() async throws {
    let options = try BigDL.parseOptions([
        "https://example.com/file.bin",
        "--threads", "8",
    ])

    #expect(options.async == true)
    #expect(options.threads == 8)
}

@Test func chunkSizeImpliesAsync() async throws {
    let options = try BigDL.parseOptions([
        "https://example.com/file.bin",
        "--chunk-size", "25MB",
    ])

    #expect(options.async == true)
    #expect(options.chunkSize == 25_000_000)
}

@Test func chunkSizeAndThreadsCanBeCombined() async throws {
    let options = try BigDL.parseOptions([
        "https://example.com/file.bin",
        "--chunk-size", "25MB",
        "--threads", "8",
    ])

    #expect(options.async == true)
    #expect(options.chunkSize == 25_000_000)
    #expect(options.threads == 8)
}

@Test func throwsOnMissingURL() async throws {
    #expect(throws: BigDL.OptionsError.self) {
        try BigDL.parseOptions(["--async"])
    }
}
