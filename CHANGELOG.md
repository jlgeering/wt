# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-02-25

### Fixed

- Restored Windows cross-build support by guarding single-key terminal input paths behind target-aware OS checks.
- Improved shared display-width handling for table output so `wt list` and picker formatting stay aligned consistently.

### Changed

- Added a scripted release workflow (`mise run release -- <X.Y.Z>`) that validates version/changelog state and publishes draft-verified releases.
- Standardized GitHub Release artifact packaging for macOS, Linux, and Windows with stable file names and `SHA256SUMS`.
- Updated release documentation to make changelog-driven notes and binary asset publication mandatory.

## [0.1.0] - 2026-02-25

### Added

- Initial public GitHub release for `wt`.
- Core worktree management commands: `list`, `new`, `rm`, and `init`.
- Shell integration support via `wt shell-init` for `zsh`, `bash`, `fish`, and `nu`.

[0.1.1]: https://github.com/jlgeering/wt/releases/tag/v0.1.1
[0.1.0]: https://github.com/jlgeering/wt/releases/tag/v0.1.0
