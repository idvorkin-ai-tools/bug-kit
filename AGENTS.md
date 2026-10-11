# Working in BugKit

Use Beads for all repository task tracking. Run `bd prime` at the start of a session and after context recovery, then `bd ready` or `bd list --status=in_progress`. Create a bead before new work, mark it `in_progress`, and close it only after the work and its required validation are complete. Link related GitHub issues with `--external-ref`; GitHub remains the intake for reports and the review surface for PRs.

All git worktrees share the main checkout's Beads database. Issue data lives in Dolt, outside code branches; `.beads/config.yaml` and `.beads/metadata.json` are tracked configuration. Use `bd dolt pull` and `bd dolt push` to sync issue data. JSONL exports are optional interchange files, not backups or the source of truth.

Every change, including docs-only changes, goes through no-mistakes before merge. Keep its pipeline fixes, follow its branch-sync instructions, and merge only after required checks pass and the user has authorized merging. Do not bypass it with a direct push or by merging a PR that skipped the pipeline.

Only one simulator on this Mac at a time: before booting, check xcrun simctl list devices booted and wait until it's empty; shut yours down when done.

Before starting any simulator or live test, run `xcrun simctl list devices booted`. If another agent has a device booted, wait. Use one disposable simulator, bound test commands, and shut it down when its test step ends. Avoid unbounded `tail -f` watchers. Use `/bin/ls` or `rg` instead of the inherited `ls` alias.
