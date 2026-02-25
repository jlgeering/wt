# Agent Workflow Prompt Cookbook

Use these prompt templates to drive an agent through repetitive bead-driven delivery.

Primary goals:

- keep long sessions moving without re-explaining context
- make pause/restart across sessions fast and reliable

## Default Loop Prompt

```md
Run the delivery loop continuously:

1) Pick the next ready bead.
2) Claim it.
3) Implement and validate.
4) Update and close the bead.
5) Sync/export tracker state.
6) Commit for that bead.
7) Repeat.

Rules:
- Use mise-managed commands/tools only.
- Create follow-up beads when new scoped work appears.
- Keep one commit per finished bead.
- Stop only when blocked or when I say stop.
```

## "Wrap It Up" Prompt

```md
Wrap it up for the current bead:
- Update bead status/details.
- Create follow-up beads if needed.
- Sync/export tracker state.
- Commit the bead work.
- If on a non-main branch, rebase on main if appropriate.
Then report what was done and the next bead.
```

## Single-Bead Prompt

```md
Take bead <ID> end-to-end:
- Claim it.
- Implement and validate.
- Close it.
- Sync/export tracker state.
- Commit.
If you uncover additional bounded work, create follow-up beads before finishing.
```

## Queue-Drain Prompt

```md
Drain the ready queue with the standard bead loop.
After each bead: close, sync/export, and commit before starting the next one.
Pause only for blockers, destructive actions, or explicit product decisions.
```

## Long-Session Prompt

```md
Run continuously in bead loop mode for a long session.

Conventions:
- one active bead at a time
- one commit per finished bead
- after each bead: close, sync/export, commit, then continue
- when creating follow-up work, create new beads immediately

Every status update should include:
- current bead
- current step
- what remains
```

## Pause / Checkpoint Prompt

```md
Checkpoint and pause:

1) Update the current bead notes with:
   - completed work
   - remaining work
   - exact next command/step
   - validation status
   - touched files
   - branch + latest commit SHA
2) Sync/export tracker state.
3) Report a short restart brief I can paste into a new session.
```

## Resume Prompt

```md
Resume from checkpoint:

1) Find in-progress bead(s).
2) Open the active bead and read notes.
3) Continue from the recorded next step.
4) Keep bead-loop conventions (close, sync/export, commit per finished bead).
```

## Reporting Prompt

```md
Work the next bead and include a short report after commit:
- bead ID + title
- what changed
- validation run
- commit SHA
- follow-up beads created (if any)
- next bead
```
