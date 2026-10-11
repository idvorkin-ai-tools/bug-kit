# Pulling reports off devices, and filing each once

## What is on the device

Every app uses the same layout in its data container:

| Path | What |
|---|---|
| `Documents/logs/<prefix>-<yyyyMMdd-HHmmss>.jsonl` | one session log per launch (`{"type", "t", …}`), pruned after 30 days unless a report names it |
| `Documents/bugs.jsonl` | one line per report |
| `Documents/bugs/<stamp>/` | the report's screenshot and extra files |
| `Documents/crashes/` | MetricKit payloads `<stamp>.json`, plus the app's own `signal-<epoch>.txt` and `exception-<epoch>.txt` |

Also copy any system inbox the app depends on. EA found 12 undelivered WatchConnectivity transfers in `Documents/Inbox/com.apple.watchconnectivity/` (EA #197). List such folders in the app's `pull_extra` and `pull-reports.sh` copies them next to `logs/`.

## The copy

```sh
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier <bundle-id> --source Documents/logs --destination <dir>/logs
xcrun devicectl device copy from --device <id> --domain-type systemCrashLogs --source / --destination <dir>/system
```

- **Directories:** a directory source lands as a directory with the destination's name.
- **Find devices with `xcrun devicectl list devices --json-output <file>`.** Take physical iPhones and iPads, and name them by `hardwareProperties.marketingName`. Never commit a device id. CG keeps its ids in gitignored `*.local` files read by `devices.sh` (CG PR #241). BugKit's scripts need no ids at all.
- **Locked devices:** the copy works over the local network while the device is locked, if it has been unlocked once since boot. Verified 2026-10-10 against a phone with `passcodeRequired: true`. `xcrun devicectl device info lockState --device <id>` tells you which state the device is in.
- **Reachability:** the first copy is the reachability probe. Later copies of `bugs/` and `crashes/` may fail only because nothing exists yet, which is not an error (CG `pull-logs.sh`).
- **Noise:** "No provider was found" lines are noise.
- **"socket was closed unexpectedly"** means the device was busy or locked. Run again.
- **The current session's log** is copied as it stands, partly written.
- **A failed copy must stop a script that processes what it copied**, or a stale copy is processed as new (EA `pull-tracks.sh`).

`scripts/pull-reports.sh` does all of this for every app and device into `~/tmp/agent/bugs/<app>/<device>/`, the same tree the listener uses.

## Checking for unfiled reports

`scripts/pull-reports.sh --check` copies only `bugs.jsonl`:
- It prints one line per report that has no issue yet: `new <app> <device> <reported_at> <note>`.
- The exit code is 1 when there are new reports, 0 when clean, and 2 when the issue lookup failed.

Give a check like this a stable, machine-readable line. CG's monitor matched `new:` and went silent forever when the check's output changed to `new (<device>):` (after CG PR #241).

## Filing once

Each issue body carries `<!-- bug:<reported_at> -->`. BugKit reports also carry `<!-- bug-id:<id> -->`. Filing skips a report whose marker is already in an issue.

- **A failed look at the existing issues stops the filing.** Otherwise everything would be filed again (CG 6fed157).
- **The title** is the note's first line that has words, with list bullets stripped and cut to 80 characters (CG 002e088).
- **Never upload the screenshot to a public repo.** Name its path on the Mac (CG 509da33). EA's older script hosted images on a gist.
- **The same report pulled from two folders is filed once.** Add each filed marker to the in-memory list straight away (CG `file-bugs.sh`).
- **The apps' marker dedupe has holes:**
  - An issue filed by hand, or by an older script, without the marker is invisible to it. CG's report of 2026-10-08T04:00:59Z still shows as unfiled although an issue was said to cover it (#233).
  - So the listener also treats a note whose first 60 characters already appear in an issue as filed, and logs it as `possible_duplicate`.
  - When you file a report by hand, paste the marker.
- **Older lines can be invalid JSON.** EA's older notes could hold a raw newline, which splits one report over two lines. Readers log and skip such lines, never die on them, and split only on `\n`: Python's `splitlines()` also breaks on U+2028, which JSON allows inside a string.
- **beads instead of GitHub:**
  - MM files with `bd create "<title>" -t bug -p 2 -l from-app -d "<description>"` and writes the bead id back into the report.
  - The listener does the same through `bd create --json` in the app's repo.

## After filing: the fix

These steps come from EA and CG DEBUGGING.md and from MM AGENTS.md.

1. Find or write the user story the report belongs to. A bug gets an `Issues:` line; a request becomes a story.
2. Open the named log at the report's `session_t_ms` with `scripts/log-tool.sh at <log> <session_t_ms> 5`. Use `around <log> 15:10:00 10` when someone names a wall time, `summary <log> --drop frame` to skip per-frame noise, and `errors` or `types` for an overview. Put what it shows on the issue as a comment.
3. If the log cannot explain it, add the event that would, deploy, and wait for the next report. Never ship a guessed fix.
4. Make one commit per issue, verified on the cheapest rung. Close the issue once the build is on the device, with a comment naming the rung and the log line that proves the fix.
