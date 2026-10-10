# bug-kit

One bug-report library for every iOS app, and a Mac listener that pulls new reports off the iPhone and iPad and
files each one once.

- **`BugKit`**, a Swift package (iOS 17+, builds on macOS for host tests). Shake, a button or ⌘I opens one
  dialog: a note, a screenshot thumbnail, and **Log it** / **Log it and another**. Each report is one line in
  `Documents/bugs.jsonl` and a folder `Documents/bugs/<stamp>/`.
- **`listener/bug-listener`**, an always-on loop on the Mac. It polls every reachable iPhone and iPad with
  `devicectl`, copies each new report with its session log and crash logs, files it to the app's tracker
  (GitHub issues, beads, or nothing), and tells the driver through an inbox file and a Herdr notification.

It was extracted from three apps that each grew their own copy: Exercise Analyzer (EA), Context Grabber's native
app (CG) and Magic Monitor (MM). Each fix below had to be made three times. Now it is made once.

## Contents

- [The principles](#the-principles), the important part
- [Adding BugKit to an app](#adding-bugkit-to-an-app)
- [The report format](#the-report-format)
- [The listener](#the-listener): install, run in a Herdr pane, or run under launchd
- [Developing BugKit](#developing-bugkit)

## The principles

These come from months of fixing bugs on devices the agent cannot see. Sources: EA and CG issue numbers link to
their public repos. MM ids (`mmn-…`) and story numbers refer to its own repo. "device-debug-loop" is
`dev-inner-loop/device-debug-loop.md` in chop-conventions.

### Logging

1. **Instrument before theorizing: logs, not guesses.** A symptom that only shows on a device gets a log event, a
   deploy and a pull before it gets a fix. If there is no instrumentation, there is no fix attempt yet: add the
   event and wait for the next report. Never ship a second guessed fix.
   - EA's HDR washout (2026-09-12) took two theory-based fixes before anyone added logging. Then the author said
     "add whatever extra logs you need".
   - The iPad sync (EA #231, 2026-10-09) prompted: "I don't want guessing. I want logs. Make sure there are logs
     on everything."
   - Instrumentation that settled bugs: EA's `clock` event ([#23]), the `photos_fetch` timing ([#35]),
     `watch_scene` showing the preview gate never opened ([#38]), and CG's mic-arm log that turned a silent first
     call into evidence (CG [#102]).
   - When you report a cause, give only what the logs show. Label everything else unknown.

2. **One JSON Lines session log per launch.** Use `Documents/logs/<app>-<yyyyMMdd-HHmmss>.jsonl`, with one event
   per line: `{"type": "<event>", "t": <ms since launch>, …fields}`.
   - Write it unbuffered, so a crash loses nothing.
   - Keep it in Documents, so the Files app shows it and `devicectl` can copy it.
   - Numbers stay numbers, never strings, so `jq 'select(.t > 57000 and .t < 60000)'` works.
   - The first line names the device, the system and the build.
   - Delete logs older than 30 days at launch, except a log that a report in `bugs.jsonl` names. Log one
     `logs_pruned` line even when nothing was deleted.
   - Sources: EA DEBUGGING.md, EA [#72], CG story 141 and story 145.

3. **A periodic status line.** For anything that can go quiet or get stuck, log a status line every few seconds
   with inputs, outputs, counters and state.
   - An event logged once misses the moment a problem started. A status line shows the minutes before every
     report.
   - Examples: EA's `clock` every 5 s ([#23]), `watch_heartbeat` once a second with `gap_ms` ([#122]),
     `offline_progress` with the memory footprint, and `sync_status` every 30 s while in front ([#231]).
   - Source: device-debug-loop.

4. **Log the scene phase and interruptions.** That means foreground and background, camera and audio
   interruptions, and protected data while the device is locked.
   - A log that stops mid-stream with no crash report means iOS suspended the app. Without these lines, nobody
     can tell a suspension from a crash.
   - Examples: CG's `timer_interruption` (a phone call), EA's `sync_app` foreground/background ([#231]), and
     `watch_reachable` with `app_state` and `protected_data`.
   - Source: device-debug-loop.

5. **Log the silent passes and the success paths, not only errors.**
   - A pass that found nothing logs that it found nothing.
   - A retry that worked logs that it worked.
   - "No line" must never be the signal, because it cannot be told apart from "never ran".
   - Examples: EA's sync logs every step on every pass, including `sync_read` when nothing changed, and one line
     per file written (EA [#231], commit f2963ca). `logs_pruned` logs even at zero ([#72]).
   - Log a failure once per spell, not once per retry. Put the deciding numbers in fields, not in prose.
   - BugKit's own dialog follows this rule:
     - it logs `bug_report_open` (source, screen, whether a screenshot was taken, which controller it opened
       over), `bug_report`, and `bug_report_cancel`;
     - each step that fails is its own `error` event (`bug_folder`, `bug_screenshot`, `bug_extra_files`,
       `bug_index`), and the report is still saved;
     - `bug_report` carries `index_written`.

6. **Verify the fix with a log line, not by asking the user.** For example `watch_inbox stuck 14 recovered 2`
   (EA [#197]). Name the rung where you verified it ("host tests", "simulator", "on the phone"). An unnamed rung
   makes the next session verify it again. Source: device-debug-loop, ios-test-ladder.

7. **Keep the events after the fix.** They are regression guards: the next time the symptom appears, the evidence
   is already in the log, and the cost of an event that stays is near zero. Source: the log-before-theorizing
   feedback, 2026-09-12.

### Reports

8. **A report names its log file and the moment.**
   - Every report carries `log` (the session log's path) and `session_t_ms` (milliseconds into that log). A reader
     goes straight from the note to what the app was doing at that second.
   - Every report also carries the screen, the build and the commit, so a log from before the fix is never read as
     evidence about the fix.
   - The app's logger gets a `bug_report` event, so the report is in the session log too, even when `bugs.jsonl`
     could not be written.
   - Sources: EA story 022, CG story 142, MM mmn-660 (the iPad's reports named "unknown" as the commit).

9. **Capture the screenshot before the dialog appears, and present the dialog from the topmost view controller.**
   - A screenshot taken after the sheet is up shows the sheet.
   - Presenting from the root replaced a sheet that was already up: a shake from EA's Workouts sheet closed that
     sheet ([#41]).
   - `BugReporter.open` snapshots the key window, then walks `presentedViewController` to the top and presents
     there.
   - A second shake while the dialog is up does nothing, so it cannot wipe a half-typed note.

10. **"Log it and another".**
    - It saves the report exactly as "Log it" does, then opens a fresh, empty report.
    - The next report keeps the same moment and screenshot, because the dialog now covers the screen.
    - Several problems seen at once take one shake, not one shake each.
    - Sources: EA [#212] (story 022), MM story 061 (mmn-2jn).

11. **A locked index append.**
    - Two reports saved together (Log it and another, with the first save still writing) each opened
      `bugs.jsonl`, sought to the same end and wrote. The later write overwrote the earlier one (MM mmn-cfr, fixed
      in 5f6d03a).
    - `BugStore.append` holds one process-wide lock and writes with `O_APPEND`. A host test runs 64 appends at once
      and expects 64 valid lines.
    - Folders are unique too: `-2`, `-3` are added within one second, and the directory create itself is the
      "taken" test (MM story 061).

12. **Every report has an `id`.**
    - The older apps keyed reports on `reported_at` to the second, and two reports in one second ("another") share
      that key.
    - BugKit's `id` is a UUID, and `reported_at` has milliseconds.
    - The listener keys old-format lines on `reported_at`, as their `file-bugs` scripts did.

### Filing and fixing

13. **Never upload screenshots to a public repo.**
    - A screenshot can show health data, places or a journal. The issue names the screenshot's path on the Mac
      and uploads nothing: CG story 143, commit 509da33.
    - EA's older `file-bugs` hosted images on a gist ([#24]). BugKit's listener does not.

14. **One report = one issue = one commit.**
    - Every report becomes one issue, filed once: a marker `<!-- bug:<reported_at> -->` / `<!-- bug-id:<id> -->`
      in the body makes filing idempotent.
    - Every fix is one commit, or one PR, that names its issue (`Fixes #N`). Never bundle fixes.
    - Close the issue once the build is on the device, with a comment that says what was verified where.
    - A bug reported by voice gets an issue too, so the trail is complete.
    - Before fixing, find or write the user story the report belongs to.
    - If looking up the existing issues fails, stop filing rather than file everything again (CG 6fed157).
    - Sources: EA AGENTS.md, MM AGENTS.md, CG AGENTS.md ("one PR per issue").

### Crashes and hangs

15. **MetricKit crash and hang capture, plus the app's own last-resort files.**
    - MetricKit hands the app its own crash and hang diagnostics at the next launch. Write each payload to
      `Documents/crashes/<stamp>.json` and announce it once in the new session log as `crash_report`.
    - MetricKit can take days on a development build, so also keep a signal handler's `signal-<epoch>.txt` and an
      uncaught exception's `exception-<epoch>.txt`. Each is announced once.
    - A log that just stops, with no crash file at all, is a kill from outside the process, most often the memory
      limit.
    - Sources: EA story 036 (42b50ff), EA [#87], CG story 144.

16. **The main thread is on a watchdog: never make synchronous system calls there in bulk.**
    - On the iPad, iOS killed EA with `0x8BADF00D` (scene-update, 10 s). The iCloud sync had asked for downloads
      file by file on the main thread at every `NSMetadataQuery` update. That was thousands of synchronous
      FileProvider XPC calls.
    - The fix: download requests left the main thread and are asked once per file (EA [#231], f2963ca).
    - An earlier `0x8BADF00D`: a camera session released on the main thread waited on its busy capture queue
      (EA [#86], d4afadd).
    - What to do:
      - When MetricKit reports a hang, read the main thread's stack first.
      - Keep FileProvider, `NSFileCoordinator` and AVFoundation teardown off the main thread.
      - Log how long each such pass takes.

### Getting reports off the device

17. **Pull with `devicectl`, no cables or Xcode needed.**

    ```sh
    xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
      --domain-identifier <bundle-id> --source Documents/bugs.jsonl --destination <file>
    ```

    - A directory source copies to a directory of that name.
    - It works over the local network while the device is **locked**, as long as it has been unlocked once since
      boot. Verified 2026-10-10 against an iPhone with `passcodeRequired: true`: files and folders both copied.
    - `xcrun devicectl device info lockState` reports the lock state, and the listener logs it with every copy.
    - Find devices with `xcrun devicectl list devices --json-output <file>`. Never hard-code device ids.
    - "No provider was found" lines are noise.

18. **An always-on listener, not a human remembering to pull.**
    - Reports used to leave a device only when an agent ran `just pull-logs` by hand, against one hard-coded
      phone, so iPad reports sat unread.
    - The listener polls every device and every app, files each report once, and tells the driver.
    - The listener follows its own rules: every poll, device, copy, report and filing outcome is a JSON line in
      `listener.log`.

[#23]: https://github.com/idvorkin/exercise-analyzer/issues/23
[#24]: https://github.com/idvorkin/exercise-analyzer/issues/24
[#35]: https://github.com/idvorkin/exercise-analyzer/issues/35
[#38]: https://github.com/idvorkin/exercise-analyzer/issues/38
[#41]: https://github.com/idvorkin/exercise-analyzer/issues/41
[#72]: https://github.com/idvorkin/exercise-analyzer/issues/72
[#86]: https://github.com/idvorkin/exercise-analyzer/issues/86
[#87]: https://github.com/idvorkin/exercise-analyzer/issues/87
[#122]: https://github.com/idvorkin/exercise-analyzer/issues/122
[#197]: https://github.com/idvorkin/exercise-analyzer/issues/197
[#212]: https://github.com/idvorkin/exercise-analyzer/issues/212
[#231]: https://github.com/idvorkin/exercise-analyzer/issues/231
[#102]: https://github.com/idvorkin/context-grabber/issues/102

## Adding BugKit to an app

1. Add the package. In Xcode, use **File › Add Package Dependencies** with `https://github.com/idvorkin/bug-kit`.
   With XcodeGen, add this to `project.yml`:

   ```yaml
   packages:
     BugKit: { url: https://github.com/idvorkin/bug-kit, branch: main }
   targets:
     MyApp:
       dependencies: [{ package: BugKit }]
   ```

2. Optionally, bake the commit into Info.plist as `BugKitCommit`, for example
   `BugKitCommit: $(GIT_COMMIT)` set from `git rev-parse --short HEAD` in a build script. Without it, reports say
   "unknown".

3. Create one reporter at launch, give it the app's hooks, and attach it to the root view:

```swift
import BugKit
import SwiftUI

@main
struct MyApp: App {
  @StateObject private var model: AppModel
  @StateObject private var reporter: BugReporter

  init() {
    let model = AppModel()
    _model = StateObject(wrappedValue: model)
    _reporter = StateObject(wrappedValue: BugReporter(hooks: BugReporterHooks(
      screen: { model.screenName },                              // "home", "playback"
      context: { ["exercise": .string(model.exercise), "playhead": .double(model.playhead)] },
      sessionLog: { (model.log.relativePath, model.log.msSinceStart) },  // "logs/app-20261010-150000.jsonl", 84442
      logger: { event, fields in model.log.event(event, fields) },  // bug_report lands in the session log
      extraFiles: { folder in                                    // optional: e.g. the clip at the playhead
        try await model.exportClip(to: folder.appendingPathComponent("clip.mov"))
        return ["clip.mov"]
      })))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .bugReporting(reporter)  // shake anywhere, or ⌘I on a hardware keyboard
    }
  }
}

// Anywhere a button is easier than a shake (an iPad on a stand):
BugReportButton(reporter: reporter)
```

- `reporter.shakeEnabled = false` ignores shakes, for example during a run where the phone is in a pocket (EA
  story 037).
- `reporter.lastStatus` says "Problem logged. Thanks." after a save, for a status line.

## The report format

`Documents/bugs.jsonl` has one line per report, newest last. Keys are sorted, and paths are relative to Documents.

```json
{"app":"Exercise Analyzer","build":"1.0 (42)","bundle":"com.example.app","commit":"ab4f1a5",
 "context":{"exercise":"kettlebell-swing","playhead":12.5},"device":"iPhone18,1 iOS 27.0",
 "files":["bugs/20261010-143000/clip.mov"],"folder":"bugs/20261010-143000",
 "id":"6F1C…","log":"logs/swing-20261010-150000.jsonl","note":"counted 1 rep, there were 13",
 "reported_at":"2026-10-10T14:30:00.250Z","screen":"playback","screenshot":"bugs/20261010-143000/screen.png",
 "session_t_ms":84442}
```

(The example is wrapped here. On disk each report is one line.)

| Field | Meaning |
|---|---|
| `id` | UUID; the key for the seen-store, the issue marker and the inbox |
| `reported_at` | ISO 8601 UTC with milliseconds |
| `app`, `bundle`, `build`, `commit` | which build; `commit` is from `BugKitCommit`, else "unknown" |
| `device` | hardware model and OS, never the device's user-given name |
| `screen`, `note` | where it happened, and what the user typed |
| `log`, `session_t_ms` | the session log's path and the moment in it |
| `screenshot`, `folder`, `files` | the screenshot, the report's folder `bugs/<yyyyMMdd-HHmmss>[-n]`, and the app's extra files |
| `context` | whatever the app attaches, as JSON values |

## The listener

`listener/bug-listener` is a [uv](https://docs.astral.sh/uv/) script that uses Typer. uv installs its dependencies
on first run. It needs Xcode's `devicectl` with each device paired, `gh` logged in for GitHub trackers, and `bd`
for beads.

### Configure

Copy the example to `~/.config/bug-kit/apps.json` and edit it. Only `apps.example.json` is in the repo.

```sh
mkdir -p ~/.config/bug-kit
cp listener/apps.example.json ~/.config/bug-kit/apps.json
```

Each app needs:

- `name`, the folder name under `~/tmp/agent/bugs/`;
- `bundle`, the bundle id;
- `repo`, the local checkout;
- `tracker`, one of `{"kind": "github", "repo": "owner/name"}`, `{"kind": "beads"}` (filed with `bd create` in
  `repo`), or `{"kind": "none"}` (inbox and notification only).

Optional: `log_dir` (default `Documents/logs`, for older reports whose `log` is a bare file name) and `crash_dir`
(default `Documents/crashes`). The top-level `poll_seconds` defaults to 300.

### What one poll does

1. It lists devices with `xcrun devicectl list devices --json-output`: physical iPhones and iPads only, named by
   model (`iphone-17-pro`, `ipad-air-11-inch-m3`).
2. It probes each device with `devicectl device info lockState`. That proves the device is reachable and records
   whether it is locked.
3. For each app, it copies `Documents/bugs.jsonl`. Each line's key is its `id`, or `reported_at` for older lines.
4. For each key not in `~/tmp/agent/bugs/seen.json`:
   1. it checks the tracker for the issue marker, because the app's own `just file-bugs` may already have filed
      it;
   2. it copies the report's folder, the session log it names, and the app's crash folder to
      `~/tmp/agent/bugs/<app>/<device>/`;
   3. it files the report: for GitHub, the screenshot's local path is named, never uploaded;
   4. it appends a line to `~/tmp/agent/bugs/inbox.jsonl` and, if `herdr` is on PATH, sends
      `herdr notification show`.
5. If filing fails, the report stays unseen and the next poll tries again.

The first time the listener meets an (app, device) pair, it marks every report already there as seen without
filing it, because the apps' own `just file-bugs` filed those. `--backfill` files them instead, and still skips
any that already have an issue.

Every step is a JSON line in `~/tmp/agent/bugs/listener.log`:

- `poll_start`
- `devices`
- `device` (reachable, locked, ms)
- `copy` (source, ok, ms, locked, stderr on failure)
- `index`
- `baseline`
- `report`
- `file` (outcome: `filed`, `already_filed`, `would_file`, `none` or `error`)
- `tracker_error`
- `notify`
- `poll_end`, with counts

A poll that throws is logged with its traceback as `poll_error`, and the loop goes on.

```sh
jq -c 'select(.event=="copy" and .ok==false)' ~/tmp/agent/bugs/listener.log   # every failed copy
jq -c 'select(.event=="poll_end")' ~/tmp/agent/bugs/listener.log               # one line per poll
```

### Run it

```sh
listener/bug-listener --once --dry-run   # copy and print what it would file; files nothing, writes no state
listener/bug-listener --once             # one real poll
listener/bug-listener                    # forever, every poll_seconds
listener/bug-listener --interval 60      # while someone is actively testing
listener/bug-listener --once --dry-run --backfill   # what first contact would file without the baseline
```

**In a Herdr pane.** Open a pane in the driver's workspace and run `~/gits/bug-kit/listener/bug-listener`. The pane
shows one short line per step. Notifications come from `herdr notification show`.

**Under launchd.** Save this as `~/Library/LaunchAgents/com.example.bug-listener.plist`, replacing `YOU` with your
user name, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.bug-listener.plist`. PATH
must reach `uv`, `gh`, `bd` and `herdr`. A login agent (gui domain) is required, because `gh` reads its token from
the login keychain.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.bug-listener</string>
  <key>ProgramArguments</key>
  <array><string>/Users/YOU/gits/bug-kit/listener/bug-listener</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/Users/YOU/tmp/agent/bugs/launchd.out</string>
  <key>StandardErrorPath</key><string>/Users/YOU/tmp/agent/bugs/launchd.err</string>
</dict>
</plist>
```

Stop it with `launchctl bootout gui/$(id -u)/com.example.bug-listener`.

## Developing BugKit

```sh
swift test   # host tests, ~1 s
```

The host tests cover:

- the format round trip and its keys;
- 64 concurrent appends giving 64 valid lines;
- unique folders, including 32 created at once within one second;
- the "Log it" and "Log it and another" flow;
- the writer's hooks: the logger receives `bug_report`, and the extra files land in the report's folder;
- a failing hook, which is logged while the report still saves.

The UI (shake, sheet, presenter, ⌘I) is iOS only. Without a simulator, the most you can do is typecheck it against
the iOS SDK:

```sh
xcrun --sdk iphoneos swiftc -typecheck -swift-version 6 -target arm64-apple-ios17.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" Sources/BugKit/*.swift
```

The dialog's real check is an app on a device: shake, type a note, tap Log it and another, type a second note,
tap Log it. Then the listener should file two reports, each naming its log.
