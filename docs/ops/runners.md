# Runners: what keeps watching while nobody is

## The listener (always on)

`listener/bug-listener` polls every device and app every 5 minutes. It files each new report once, writes `inbox.jsonl`, and sends a Herdr notification. Run it in a Herdr pane, or under launchd (see the README).

The listener replaces the per-app monitors below for filing. Those are still useful while an agent is testing with the person.

## Monitor rather than `/loop`, while someone is testing

EA and CG each have `scripts/bugs-monitor.sh`, which runs the bugs check every minute and prints one line per new report, each report once. Arm it as a persistent Monitor:

```
Monitor(command: "scripts/bugs-monitor.sh", description: "new shake reports on the phone", persistent: true)
```

A Monitor wakes the model only when a report appears. `/loop 5m just bugs-check` wakes it every five minutes to find nothing, so it is the fallback when Monitor is not available.

With BugKit, the monitor's command can be a loop over `scripts/pull-reports.sh --check`, which prints only `new …` lines:

```sh
while true; do scripts/pull-reports.sh --check 2>/dev/null | grep '^new '; sleep 60; done
```

That loop prints the same lines every pass. Dedupe them as EA's monitor does with its `seen` list, or let the listener file them.

## Long builds and tests in the background

- **The Bash tool caps a foreground command at 10 minutes**, and `xcodebuild test` on a busy Mac runs longer. Run it with `run_in_background`, writing to a log file, and wait for the task notification.
- **If you poll a log for `TEST SUCCEEDED|FAILED`, delete or rotate it first.** A wait loop once matched the previous run's "TEST FAILED" (CG, 2026-10-07).

## The no-mistakes pipeline

no-mistakes is a local gate that takes committed work on a feature branch through these steps: intent, rebase, review, test, document, lint, push, PR, CI. Each repo configures it in `.no-mistakes.yaml` on main.

How the apps configure it:
- **Each app:** `commands.test: "just test"` (the host rung, about 1 s) and `no_ci: true`.
- **CG:** `protected_paths` keeps auto-fix commits off the native surface. Its test instructions say: no simulator, no deploy, name the rung, and list what only the phone can show.

Gotchas from runs on 2026-10-07:
- **`axi status` reports only the checked-out branch.** After a branch switch use `axi status --run <id>`. A watcher left polling `status` looped for an hour.
- **`axi run` and `axi respond` return after an 8-minute hold** with `error: wait … elapsed`. That is not a failure: run them in the background and reattach.
- **"Test agent exceeded its invocation budget"** is a cut, not a test failure.
- **The pipeline refuses to start while untracked files are in the tree.** Put other agents' folders in `.git/info/exclude`.
- **A run keeps its own test simulator and xcodebuild alive.** Pause or cancel it when the Mac is slow (mac-driver).

## One agent, one simulator, at a time

- Several agents each booting simulators drove a 16 GB Mac's load average to about 950 and filled swap (2026-10-07). Since then only one agent runs at a time, with at most one simulator.
- Before handing over, check that nothing is left running: `xcrun simctl list devices booted` and `pgrep -x xcodebuild`.
- Agents end a turn with "DONE, simulator shut down".
- A bug-pass prompt that works: "Pull logs and reports off the phone and iPad, file an issue for each new report, fix (one commit per bug, verified on the cheapest rung), redeploy, then write an update to `~/tmp/agent/notes/bug-pass/<repo>.md`."
- Write commit messages with a quoted heredoc (`<<'EOF'`). An unquoted one once ran a backticked `just ipad` inside the message text, which started a signing build.
