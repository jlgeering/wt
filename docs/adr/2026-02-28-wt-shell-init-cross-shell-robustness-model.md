# ADR: Shell-Init Cross-Shell Robustness Model

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt shell-init` now supports `zsh`, `bash`, `fish`, and `nu`, with a mix of:

- shared completion metadata (`src/lib/cli_surface.zig`)
- partially shared runtime wrapper behavior (POSIX shells share one body, Nushell is separate)
- shell-specific stream and TTY handling details

Recent Nushell work exposed a fragility: no-arg picker behavior needed explicit stderr routing to `/dev/tty` (with fallback) to keep interactive picker UX reliable in Nu pipeline execution contexts. That fix was added in commit `555df30` (`Fix Nushell picker TTY handling and add runtime parity coverage`), but the underlying concern is broader than a single shell bug.

We need a decision for scaling shell support without repeating wrapper drift and stream/TTY regressions.

## Decision

Adopt a **Behavior Contract + Shell Adapter** model for shell-init generation.

1. Define one canonical runtime behavior contract for wrapper flows.
2. Keep per-shell emitters, but treat them as adapters to the same contract.
3. Treat shell-specific stream/TTY behavior as explicit, documented escape hatches with required tests.
4. Expand test strategy from template-shape checks to contract-level runtime assertions across shells.

### Canonical Runtime Contract

The shared contract covers:

- no-arg `wt` flow:
  - invoke `wt __pick-worktree`
  - preserve repo-relative subdirectory when present
  - fall back to selected root when subdirectory is missing
  - emit entered-location report after successful `cd`
- `wt new|add` flow:
  - invoke `wt __new`
  - preserve repo-relative subdirectory when present
  - fall back to new worktree root when subdirectory is missing
  - emit entered-location report after successful `cd`
- pass-through flow:
  - non-intercepted commands call real binary directly
- stream and status invariants:
  - preserve command stderr visibility
  - preserve command exit semantics
  - avoid hard dependency on `/dev/tty` without fallback path

### Escape Hatch Policy

Shell-specific behavior is allowed only when:

1. the shell runtime cannot express the shared behavior safely without it, and
2. the exception is documented as an adapter rule, and
3. at least one integration test covers the exception path.

Initial explicit escape hatch:

- Nushell picker invocation may route stderr to `/dev/tty` with fallback (`try/catch`) to preserve interactive UX while remaining safe when no tty device is available.

### Options Considered

1. Keep current handwritten per-shell wrappers with ad-hoc fixes.
   - Pros: lowest short-term change.
   - Cons: continued drift risk; higher chance of repeating Nu-class bugs.
2. Full immediate unification into a shell-agnostic DSL/interpreter.
   - Pros: strongest theoretical consistency.
   - Cons: high complexity now; delays practical hardening.
3. Behavior Contract + Shell Adapter (chosen).
   - Pros: practical near-term hardening with clear scaling path.
   - Cons: still requires maintaining shell adapters, but under explicit rules.

## Failure Modes Identified (Including Recent Nu TTY Bug)

1. **Interactive picker stderr not attached to visible terminal in Nushell pipelines**
   - Symptom: picker prompts/error output can disappear from user-visible terminal context.
   - Trigger: external command capture/pipeline behavior around `| complete`.
2. **Hard `/dev/tty` dependency can fail in non-tty or restricted environments**
   - Symptom: wrapper failure before picker logic completes.
   - Trigger: `/dev/tty` unavailable or not openable.
3. **Runtime parity drift between shells**
   - Symptom: one shell diverges on `cd`, message, or exit semantics.
   - Trigger: emitter-local edits without contract-level tests.
4. **Test strategy drift from implementation reality**
   - Symptom: docs or tests imply narrower coverage than current behavior and miss new gaps.
   - Trigger: evolution of runtime/PTY tests without strategy refresh.

## Prioritized Plan

1. P0: lock contract and Nu escape hatch documentation
   - Use this ADR as canonical model.
   - Complete `wt-33t` to document/enforce Nushell stderr/TTY behavior and troubleshooting.
2. P1: strengthen runtime parity coverage
   - Extend real-shell runtime parity tests to include fish.
   - Add failure-path assertions for stderr and no-`cd` invariants.
3. P2: formalize adapter responsibilities
   - Add a compact per-shell adapter contract section in code comments/docs.
   - Keep all exceptions in one documented “escape hatch” block per shell.
4. P3: harden interactive/PTY regression coverage
   - Keep PTY picker coverage for zsh/bash/nu and expand only where a proven gap exists.
   - Ensure skip semantics remain explicit and non-flaky.
5. P4: reassess architecture when shell count or divergence grows
   - Re-evaluate a deeper generator/DSL approach only if adapter complexity materially increases.

## Consequences

- Positive:
  - Better long-term maintainability without immediate heavy rewrite.
  - Nushell-class regressions become easier to prevent via explicit contract tests.
  - Shell-specific differences become intentional and reviewable.
- Costs:
  - More explicit test and documentation maintenance.
  - Some shell-specific code remains, but now under constrained policy.

## References

- `src/commands/shell_init.zig`
- `src/lib/cli_surface.zig`
- `test/integration_shell_init.zig`
- `src/commands/pick_worktree.zig`
- `docs/adr/2026-02-23-wt-internal-picker-command-and-alignment.md`
- `docs/adr/2026-02-24-wt-internal-machine-commands.md`
- commit `555df30` (`Fix Nushell picker TTY handling and add runtime parity coverage`)
