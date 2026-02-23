# Documentation Structure

This folder contains canonical project documentation.

## Current Folders

- `specs/` - Normative behavior and data/output contracts ("what the tool does")
- `guides/` - Operational and contributor guidance ("how to use and maintain it")
- `adr/` - Architecture Decision Records ("why we chose it")

## Folder Indexes

- Specs index: [`specs/README.md`](specs/README.md)
- Guides index: [`guides/README.md`](guides/README.md)
- ADR index: [`adr/README.md`](adr/README.md)

## Plan and Archive Lifecycle

Active planning lives outside `docs/`:

- `plans/` (repo root) - Active work-in-progress plans

Archived material lives under `archive/`:

- `archive/plans/` - Completed or superseded plans
- `archive/explorations/` - Historical prototypes and explorations

Lifecycle:

1. Draft and iterate in `plans/`
2. Consolidate stable behavior into `docs/specs/`
3. Keep how-to and operational guidance in `docs/guides/`
4. Record significant decisions in `docs/adr/`
5. Move completed/superseded plans to `archive/plans/`
6. Move exploratory artifacts to `archive/explorations/`
