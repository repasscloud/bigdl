# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.2.0] - 2026-08-24

### Changed

- `--threads` and `--chunk-size` now imply `--async`, so multi-part
  downloads no longer require passing `--async` explicitly.
- Errors are now printed as a concise message instead of a raw error dump.

### Added

- `--async` flag to download files in multiple concurrent parts.
- `--threads N` option to control the maximum number of concurrent parts
  (default: 4).
- `--chunk-size SIZE` option to control the size of each part (e.g. `10MB`,
  `512KB`, `1GiB`); defaults to an even split of the file across the thread
  count.
- Automatic fallback to a single-stream download with a warning when the
  server doesn't support HTTP range requests.
- Independent per-part resume for interrupted multi-part downloads.
- `README.md` with installation, usage, and behavior documentation.

## [0.1.0] - 2026-08-24

### Added

- Initial release: single-connection download of a URL to a local file.
- Resumable downloads via `.part` files and HTTP `Range` requests.
- Progress reporting with size, percentage, speed, and ETA.
- `-h`/`--help` and `-v`/`--version` flags.
