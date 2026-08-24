# bigdl

A simple command-line downloader for large files, written in Swift. Supports
resumable single-connection downloads and concurrent multi-part downloads.

## Features

- Resumable downloads — interrupted downloads pick up where they left off
- Multi-part concurrent downloads (`--async`) for faster transfers on
  servers that support HTTP range requests
- Progress reporting with speed and ETA
- No external dependencies

## Installation

### Homebrew

```bash
brew install repasscloud/tap/bigdl
```

### From source

Requires Swift 6.3+ and macOS 15+.

```bash
git clone <repo-url>
cd bigdl
swift build -c release
```

The built binary will be at `.build/release/bigdl`. Copy it somewhere on
your `PATH`, e.g.:

```bash
cp .build/release/bigdl /usr/local/bin/bigdl
```

## Usage

```
bigdl <url> [output] [options]
bigdl --help
bigdl --version
```

### Arguments

| Argument | Description |
| --- | --- |
| `url` | URL of the file to download |
| `output` | Optional output filename (defaults to the URL's last path component, or `download.bin`) |

### Options

| Option | Description |
| --- | --- |
| `-h`, `--help` | Show help |
| `-v`, `--version` | Show version |
| `--async` | Download the file in multiple parts concurrently (implied by `--threads` or `--chunk-size`) |
| `--threads N` | Max concurrent parts (default: `4`); implies `--async` |
| `--chunk-size SIZE` | Size of each part, e.g. `10MB`, `512KB`, `1GiB` (default: total size / threads); implies `--async` |

### Examples

Basic download:

```bash
bigdl https://testfile.to/dl/1gb
```

Download to a specific filename:

```bash
bigdl https://testfile.to/dl/1gb download.bin
```

Multi-part download with 8 concurrent threads:

```bash
bigdl https://testfile.to/dl/1gb --threads 8
```

Multi-part download with fixed 25MB parts:

```bash
bigdl https://testfile.to/dl/1gb --chunk-size 25MB
```

Multi-part download with fixed 25MB parts, capped at 8 concurrent parts:

```bash
bigdl https://testfile.to/dl/1gb --chunk-size 25MB --threads 8
```

## How it works

### Single-stream downloads (default)

The file is streamed to `<output>.part`. If the download is interrupted,
running `bigdl` again with the same URL and output resumes from the existing
`.part` file's size using an HTTP `Range` request, provided the server
supports it. Once complete, the `.part` file is renamed to the final output
path.

### Multi-part downloads (`--async`)

Multi-part mode is enabled by passing `--async`, or implicitly by passing
`--threads` or `--chunk-size`. `bigdl` first issues a `HEAD` request to check
whether the server advertises `Accept-Ranges: bytes` and reports a content
length. If not supported, it prints a warning and falls back to a normal
single-stream download.

Otherwise, the file is split into byte ranges (sized by `--chunk-size`, or
evenly across `--threads` parts if `--chunk-size` is omitted). Up to
`--threads` parts download concurrently, each into its own `<output>.partN`
file. Each part resumes independently if interrupted, based on how many
bytes of that part already exist on disk. Once every part has finished, the
parts are concatenated in order into the final output file and the
intermediate `.partN` files are removed.

## Development

Run the test suite:

```bash
swift test
```

## License

See [LICENSE](LICENSE).
