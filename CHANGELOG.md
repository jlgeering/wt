# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-02-28

### Added

- Expanded `wt init` project detection to be repo-wide and cwd-invariant, with improved support for nested repositories and subfolder workflows.
- Added default symlink setup recommendations for local `mise` and Claude config paths in `wt init`.

### Fixed

- Fixed `wt init` setup execution on Windows by removing shell-wrapper assumptions and adding copy-path support.
- Improved `wt init` review reliability by handling cancel flows (`Esc`/`Ctrl-C`) and detecting ignored local files in discovered roots.
- Hardened `wt shell-init` Nushell picker handling to avoid unsafe TTY/stderr interactions in interactive selection paths.

### Changed

- Updated the release pipeline interface to require explicit version input (`mise run release -- <X.Y.Z>`) and removed file-based version handoff.
- Reworked `wt init` planning internals around `init_scan` and expanded integration/runtime test coverage for setup and shell-init picker flows.

## [0.2.1] - 2026-02-28

### Fixed

- Improved `wt rm` local-commit safety checks to ignore patch-equivalent commits, reducing false positive blocks when histories differ but content matches.
- Fixed `wt rm` local-commit base-ref resolution to follow the primary worktree branch (with detached-HEAD fallback), avoiding hardcoded `main` assumptions.
- Corrected Nushell shell-init picker behavior to avoid unsafe TTY/stderr interactions and expanded runtime parity coverage for picker flows.

## [0.2.0] - 2026-02-28

### Added

- Unified shell completion candidate generation through internal command metadata so completions stay in sync with the CLI surface.
- Expanded shell integration and parity test coverage for completion behavior and generated shell docs.

### Fixed

- Corrected multiple shell completion edge cases, including `new`/`add` positional completion in bash and support for both `nu` and `nushell` aliases.
- Improved safety and UX behavior in interactive paths, including `Ctrl-C` handling in `wt init` and avoiding `/dev/tty` stderr redirection in shell wrappers.
- Hardened worktree safety checks by detecting the current worktree from nested directories, rejecting unsafe setup paths, and preventing non-worktree path collisions.
- Fixed Windows release archive packaging in the automated release pipeline so `.zip` artifacts are emitted reliably from repo-root staging paths.

### Changed

- Updated shell-init implementation to use dedicated shell emitters, improving maintainability and parity across `zsh`, `bash`, `fish`, and `nu`.

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

[0.3.0]: https://github.com/jlgeering/wt/releases/tag/v0.3.0
[0.2.1]: https://github.com/jlgeering/wt/releases/tag/v0.2.1
[0.2.0]: https://github.com/jlgeering/wt/releases/tag/v0.2.0
[0.1.1]: https://github.com/jlgeering/wt/releases/tag/v0.1.1
[0.1.0]: https://github.com/jlgeering/wt/releases/tag/v0.1.0
