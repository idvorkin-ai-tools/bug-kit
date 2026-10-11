# BugKit

Bug reports, session logs and crash evidence for iOS apps, plus a Mac listener that pulls reports from paired iPhones and iPads and files them in GitHub, beads or a local inbox.

BugKit requires **iOS 17+**. Its report model, storage and flow also support **macOS 14+**; the reporting UI is iOS only. Building the package’s tests requires **Swift 6+** because they use Swift Testing.

- Shake, tap a button or press ⌘I to report a problem. The dialog captures a screenshot before opening and supports “Log it and another.”
- Each report carries a UUID, build, typed context, session log path and timestamp. Files stay in the app’s Documents directory until pulled.
- The listener polls every reachable paired iPhone and iPad, files reports once and names local screenshot paths without uploading images.
- An optional What's new feed connects git commits to user stories and shows recent changes in the app.

Extracted from Exercise Analyzer, Context Grabber and Magic Monitor so shared fixes reach every app.

## Quick start

Add `https://github.com/idvorkin/bug-kit` through Xcode’s **File › Add Package Dependencies**, and link the `BugKit` product. With XcodeGen:

```yaml
packages:
  BugKit:
    url: https://github.com/idvorkin/bug-kit
    branch: main
targets:
  MyApp:
    dependencies:
      - package: BugKit
```

<<<<<<< HEAD
Create one reporter at launch and attach it to your root view. This minimal app uses BugKit’s session logger:
||||||| 03dd0cb
"✓" means the app has the feature today, on its origin/main of 2026-10-10; "–" means it does not. The BugKit column gives the option or type that provides the feature.

| Feature | EA | CG | MM | BugKit |
|---|---|---|---|---|
| iOS shake gesture opens the report | ✓ | ✓ | – | `systemShake` (on) |
| Gentle shake read from motion (CG story 146) | – | ✓ | – | `gentleShake` (on) |
| A button | ✓ | ✓ | ✓ (iPad Settings) | `BugReportButton` |
| ⌘I | – | – | ✓ | `commandI` (on) |
| Return/Escape keys in the dialog | – | – | ✓ | `dialogKeys` (on) |
| Screenshot taken before the dialog | ✓ | ✓ | – (video instead) | always |
| Opens over other sheets (topmost VC) | ✓ (#41) | ✓ (#182) | – | always |
| "Log it and another" | ✓ keeps the moment | ✓ re-captures | ✓ | `another: .keepMoment` or `.recapture` |
| Speak the note (CG #239) | – | ✓ | – | `dictation` (off: needs Info.plist strings) |
| "Nothing leaves this iPad" | – | – | ✓ | `privacyNote` |
| A report `id` (UUID) and ms `reported_at` | – | – | – | always |
| Locked index append (mmn-cfr) | – | – | ✓ | always |
| Unique folders within one second | – | – | ✓ | always |
| Report names its log and the moment | ✓ | ✓ | ✓ (copies the log) | `log`, `session_t_ms`; `copySessionLog` |
| Build and commit in the report | – | ✓ | ✓ | always (`BugKitCommit`) |
| Typed context (numbers stay numbers) | – (strings) | – (strings) | ✓ (Codable) | `context: [String: JSONValue]` |
| Extra files: clip, recent segments, report.json | ✓ frame | – | ✓ | `extraFiles`, `RecentSegments`, `writeReportJSON` |
| JSON Lines session log per launch | ✓ | ✓ | ✓ | `SessionLog` (optional) |
| Periodic status line helper | ad hoc | ad hoc | ad hoc | `SessionLog.status(every:)` |
| Logs pruned at 30 days, reported ones kept | ✓ | ✓ | – | `BugStore.pruneLogs` |
| MetricKit, signal and exception files, announced once | ✓ | ✓ | – | `CrashReports` |
| Simulator hooks for reports | ✓ `SWING_BUG` | ✓ `GRABBER_BUG` | selftest script | `launchHookPrefix` |
| What's new from git and the stories (CG story 148) | – | ✓ | – | `WhatsNew`, `WhatsNewView`, `WhatsNewRow`, `scripts/whats-new.sh` |
| Pull from the phone **and** the iPad | – (one device) | ✓ (PR #241) | – | `scripts/pull-reports.sh` |
| File each report once | ✓ GitHub, gist images | ✓ GitHub, no images | ✓ beads | `listener/bug-listener` (GitHub, beads, none) |
| Always-on listener, inbox and notification | – | – | – | `listener/bug-listener` |
| Deploy to every device under the signing lock | – | – | ✓ lock (iPad only) | `scripts/deploy-all.sh` |

### Migration checklists

The order is EA first (CG's copy came from it), then CG, then MM. Each app keeps its own context, screen names and stories. One commit per step.

**Exercise Analyzer**
1. Add the package. Replace `ShakeDetector`, `BugReportSheet` and `BugReporter` in `BugReport.swift` with `BugReporter(hooks:options:)`, using `another: .keepMoment` (#212's behaviour). This fixes the unlocked `bugs.jsonl` append and the same-second folder overwrite that EA still has.
2. Hooks:
   - `context`: today's `bugContext()`, with numbers as numbers (`reps`, `playhead`);
   - `logger`: `log.event`;
   - `extraFiles`: the frame at the playhead (`frame.jpg`, story 026);
   - `sessionLog`: `("logs/" + log.url.lastPathComponent, ms)`.
3. Set `launchHookPrefix: "SWING"`, so `SWING_BUG` keeps working (`a|b` included).
4. Keep `CrashReports.swift`, or swap in BugKit's `CrashReports.shared.install(logger:)`. They are the same design, but BugKit's signal handler does not allocate and writes one file per crash, as CG's does. Swap `pruneOldLogs` for `BugStore().pruneLogs(logger:)`.
5. Point `just bugs-check` at `scripts/pull-reports.sh --check exercise-analyzer`. Stop hosting screenshots on gists if the repo is public.
6. Add What's new: `scripts/whats-new.sh` as a build phase, plus `WhatsNewRow` and `WhatsNewView`.
7. Wrap `build-device` in the signing lock, or use `scripts/deploy-all.sh exercise-analyzer --watch`.

**Context Grabber (native)**
1. Replace `BugReport.swift`, `NoteDictation.swift` and `ShakeMotion` with `BugReporter`, using `another: .recapture`, `dictation: true` and `gentleShake: true`. Set `microphoneBusy` to `{ model.call.snapshot.isActive }`.
2. Move `ShakeGesture`, `LogRetention` and `WhatsNew` out of ContextCore to BugKit's versions. They are the same code. `WhatsNew` now takes the story base URL as a parameter.
3. Switch `scripts/native/whats-new.sh` to BugKit's script with `--path native --base-url <the repo's stories URL>`.
4. Set `launchHookPrefix: "GRABBER"`.
5. Fix or retire `scripts/native/bugs-monitor.sh`. It stopped matching after PR #241 changed the check's line format; `pull-reports.sh --check` prints a stable line.
6. Wrap `native-build-device` in the signing lock, or use `scripts/deploy-all.sh context-grabber`.

**Magic Monitor**
1. On the iPad, move reports from Application Support to `Documents/bugs.jsonl` and `Documents/bugs/`, so the listener sees them.
2. Use `BugReporter` with these options:
   - `commandI`, `dialogKeys` and `another: .keepMoment`;
   - `privacyNote: "Nothing leaves this iPad."`;
   - `copySessionLog: true` and `writeReportJSON: true`;
   - `extraFiles` copying `RecentSegments.covering(…, seconds: 90)`.
   Note that BugKit's keys differ from MM's: ⌘Return logs and ⇧⌘Return logs another, because the note field is multi-line.
3. The Mac app is not iOS. Keep its SwiftUI sheet, and use `BugReportFlow` and `BugReportWriter`, which build on macOS.
4. Add `CrashReports` and `pruneLogs`. MM has neither.
5. Set the tracker to `beads` in the listener's config, and keep `just file-bugs` for the Mac's own reports.

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
    - **The marker dedupe has holes.** An issue filed by hand, or by an older script, without the marker is
      invisible to it. CG's report of 2026-10-08T04:00:59Z still shows as unfiled although an issue was said to
      cover it (#233). So the listener also treats a note whose first 60 characters already appear in an issue as
      filed, and logs `possible_duplicate`. When filing by hand, paste the marker.
    - **Old index lines can be invalid JSON.** EA's older notes could carry a raw newline, which splits one report
      over two lines. Readers log and skip such lines (`line_unreadable`). BugKit always escapes.
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

3. At launch:
   - open the session log, if the app has none of its own;
   - install crash capture;
   - prune old logs;
   - create one reporter with the app's hooks and options, and attach it to the root view.
=======
"✓" means the app has the feature today, on its origin/main of 2026-10-10; "–" means it does not. The BugKit column gives the option or type that provides the feature.

| Feature | EA | CG | MM | BugKit |
|---|---|---|---|---|
| iOS shake gesture opens the report | ✓ | ✓ | – | `systemShake` (on) |
| Gentle shake read from motion (CG story 146) | – | ✓ | – | `gentleShake` (on) |
| A button | ✓ | ✓ | ✓ (iPad Settings) | `BugReportButton` |
| ⌘I | – | – | ✓ | `commandI` (on) |
| Return/Escape keys in the dialog | – | – | ✓ | `dialogKeys` (on) |
| Screenshot taken before the dialog | ✓ | ✓ | – (video instead) | always |
| Opens over other sheets (topmost VC) | ✓ (#41) | ✓ (#182) | – | always |
| "Log it and another" | ✓ keeps the moment | ✓ re-captures | ✓ | `another: .keepMoment` or `.recapture` |
| Speak the note (CG #239) | – | ✓ | – | `dictation` (off: needs Info.plist strings) |
| "Nothing leaves this iPad" | – | – | ✓ | `privacyNote` |
| A report `id` (UUID) and ms `reported_at` | – | – | – | always |
| Locked index append (mmn-cfr) | – | – | ✓ | always |
| Unique folders within one second | – | – | ✓ | always |
| Report names its log and the moment | ✓ | ✓ | ✓ (copies the log) | `log`, `session_t_ms`; `copySessionLog` |
| Build and commit in the report | – | ✓ | ✓ | always (`BugKitCommit`) |
| Typed context (numbers stay numbers) | – (strings) | – (strings) | ✓ (Codable) | `context: [String: JSONValue]` |
| Extra files: clip, recent segments, report.json | ✓ frame | – | ✓ | `extraFiles`, `RecentSegments`, `writeReportJSON` |
| JSON Lines session log per launch | ✓ | ✓ | ✓ | `SessionLog` (optional) |
| Wall time and host-clock time on every log line (MM) | – | – | ✓ | `SessionLog(clocks: [.wall, .mono])` (off) |
| Resident memory on the status line (MM) | – | – | ✓ | `status(every:memory: true)` |
| Summarize a log, or slice it around a time or a report (EA, MM) | ✓ `log-summary` | – | ✓ | `scripts/log-tool.sh` |
| Event catalogue, `ui` with `from:`, logic version in `session_start` | ✓ | ✓ | – | [docs/ops/logging.md](docs/ops/logging.md) |
| Periodic status line helper | ad hoc | ad hoc | ad hoc | `SessionLog.status(every:)` |
| Logs pruned at 30 days, reported ones kept | ✓ | ✓ | – | `BugStore.pruneLogs` |
| MetricKit, signal and exception files, announced once | ✓ | ✓ | – | `CrashReports` |
| Simulator hooks for reports | ✓ `SWING_BUG` | ✓ `GRABBER_BUG` | selftest script | `launchHookPrefix` |
| What's new from git and the stories (CG story 148) | – | ✓ | – | `WhatsNew`, `WhatsNewView`, `WhatsNewRow`, `scripts/whats-new.sh` |
| Pull from the phone **and** the iPad | – (one device) | ✓ (PR #241) | – | `scripts/pull-reports.sh` |
| File each report once | ✓ GitHub, gist images | ✓ GitHub, no images | ✓ beads | `listener/bug-listener` (GitHub, beads, none) |
| Always-on listener, inbox and notification | – | – | – | `listener/bug-listener` |
| Deploy to every device under the signing lock | – | – | ✓ lock (iPad only) | `scripts/deploy-all.sh` |

### Migration checklists

The order is EA first (CG's copy came from it), then CG, then MM. Each app keeps its own context, screen names and stories. One commit per step.

**Exercise Analyzer**
1. Add the package. Replace `ShakeDetector`, `BugReportSheet` and `BugReporter` in `BugReport.swift` with `BugReporter(hooks:options:)`, using `another: .keepMoment` (#212's behaviour). This fixes the unlocked `bugs.jsonl` append and the same-second folder overwrite that EA still has.
2. Hooks:
   - `context`: today's `bugContext()`, with numbers as numbers (`reps`, `playhead`);
   - `logger`: `log.event`;
   - `extraFiles`: the frame at the playhead (`frame.jpg`, story 026);
   - `sessionLog`: `("logs/" + log.url.lastPathComponent, ms)`.
3. Set `launchHookPrefix: "SWING"`, so `SWING_BUG` keeps working (`a|b` included).
4. Keep `CrashReports.swift`, or swap in BugKit's `CrashReports.shared.install(logger:)`. They are the same design, but BugKit's signal handler does not allocate and writes one file per crash, as CG's does. Swap `pruneOldLogs` for `BugStore().pruneLogs(logger:)`.
5. Point `just bugs-check` at `scripts/pull-reports.sh --check exercise-analyzer`. Stop hosting screenshots on gists if the repo is public.
6. Add What's new: `scripts/whats-new.sh` as a build phase, plus `WhatsNewRow` and `WhatsNewView`.
7. Wrap `build-device` in the signing lock, or use `scripts/deploy-all.sh exercise-analyzer --watch`.

**Context Grabber (native)**
1. Replace `BugReport.swift`, `NoteDictation.swift` and `ShakeMotion` with `BugReporter`, using `another: .recapture`, `dictation: true` and `gentleShake: true`. Set `microphoneBusy` to `{ model.call.snapshot.isActive }`.
2. Move `ShakeGesture`, `LogRetention` and `WhatsNew` out of ContextCore to BugKit's versions. They are the same code. `WhatsNew` now takes the story base URL as a parameter.
3. Switch `scripts/native/whats-new.sh` to BugKit's script with `--path native --base-url <the repo's stories URL>`.
4. Set `launchHookPrefix: "GRABBER"`.
5. Fix or retire `scripts/native/bugs-monitor.sh`. It stopped matching after PR #241 changed the check's line format; `pull-reports.sh --check` prints a stable line.
6. Wrap `native-build-device` in the signing lock, or use `scripts/deploy-all.sh context-grabber`.

**Magic Monitor**
1. On the iPad, move reports from Application Support to `Documents/bugs.jsonl` and `Documents/bugs/`, so the listener sees them.
2. Use `BugReporter` with these options:
   - `commandI`, `dialogKeys` and `another: .keepMoment`;
   - `privacyNote: "Nothing leaves this iPad."`;
   - `copySessionLog: true` and `writeReportJSON: true`;
   - `extraFiles` copying `RecentSegments.covering(…, seconds: 90)`.
   Note that BugKit's keys differ from MM's: ⌘Return logs and ⇧⌘Return logs another, because the note field is multi-line.
3. The Mac app is not iOS. Keep its SwiftUI sheet, and use `BugReportFlow` and `BugReportWriter`, which build on macOS.
4. Add `CrashReports` and `pruneLogs`. MM has neither.
5. Set the tracker to `beads` in the listener's config, and keep `just file-bugs` for the Mac's own reports.

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
    - **The marker dedupe has holes.** An issue filed by hand, or by an older script, without the marker is
      invisible to it. CG's report of 2026-10-08T04:00:59Z still shows as unfiled although an issue was said to
      cover it (#233). So the listener also treats a note whose first 60 characters already appear in an issue as
      filed, and logs `possible_duplicate`. When filing by hand, paste the marker.
    - **Old index lines can be invalid JSON.** EA's older notes could carry a raw newline, which splits one report
      over two lines. Readers log and skip such lines (`line_unreadable`). BugKit always escapes.
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

3. At launch:
   - open the session log, if the app has none of its own;
   - install crash capture;
   - prune old logs;
   - create one reporter with the app's hooks and options, and attach it to the root view.
>>>>>>> origin/feat/r3-logs

```swift
import BugKit
import SwiftUI

@main
struct MyApp: App {
  @StateObject private var reporter: BugReporter
  private let log: SessionLog

  init() {
    let log = SessionLog(prefix: "app")
    self.log = log
    CrashReports.shared.install(logger: log.logger)
    BugStore().pruneLogs(logger: log.logger)
    var options = BugReporterOptions()
    options.recordInteractions = true
    options.captureAccessibility = true
    _reporter = StateObject(wrappedValue: BugReporter(
      hooks: BugReporterHooks(
        screen: { "home" },
        sessionLog: { log.position },
        logger: log.logger,
        flushLog: { log.flush() }
      ), options: options
    ))
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        Text("My app")
          .toolbar { BugReportButton(reporter: reporter) }
      }
      .bugReporting(reporter)
    }
  }
}
```

The two diagnostic options attach recent interaction breadcrumbs and a public view/accessibility snapshot to each report. See [UI diagnostics](docs/integration.md#interaction-and-accessibility-diagnostics) for coverage and semantic action hooks.

See [integration](docs/integration.md) for context, extra files, dictation, simulator hooks and What's new. Dictation is off by default; enabling it requires speech and microphone usage descriptions in Info.plist. Set `BugKitCommit` in Info.plist to include the app’s commit in reports.

## Enable each feature

Set options **before** constructing `BugReporter(hooks: ..., options: options)`, and keep `.bugReporting(reporter)` on your root view as in the quick start. The quick start enables interaction and accessibility capture explicitly; both are off by default.

### Clicks, touches and semantic actions

```swift
options.recordInteractions = true
options.interactionLimit = 200  // recent events per report; clamped to 1...1,000
```

This records touches, approximate taps/drags/long presses, UIKit control actions and scene activity. Each report gets `interactions.jsonl`; events also go to your `logger` hook. For exact SwiftUI, keyboard or VoiceOver actions, add this to the relevant action handler:

```swift
reporter.recordInteraction("open_settings", fields: ["source": "keyboard"])
```

Give views stable identifiers, such as `.accessibilityIdentifier("settings-button")`, to make events easier to locate. Automatic capture observes the active app window; it does not capture every semantic action automatically.

### Accessibility tree dump

```swift
options.captureAccessibility = true
```

Each report gets `accessibility.json`, captured before the report dialog opens. It contains the public UIKit view/accessibility hierarchy, identifiers, labels, hints, frames and traits, bounded to 500 nodes and depth 30. Text-entry subtrees and accessibility values are omitted. Some virtual SwiftUI elements may be absent. This option works independently of interaction recording. See [coverage and limitations](docs/integration.md#interaction-and-accessibility-diagnostics).

### Crash capture and automatic filing

Install crash capture once at app launch, after creating the session logger:

```swift
CrashReports.shared.install(logger: log.logger)
```

Then configure the Mac listener using [Pull and file reports](#pull-and-file-reports) below and run:

```sh
listener/bug-listener --once --backfill  # first poll: include existing reports and crashes
listener/bug-listener                   # keep polling for new evidence
```

No separate listener flag is needed for crash discovery. It polls `Documents/crashes` even when no manual bug report exists; set `crash_dir` in the app's `apps.json` entry if your app uses another directory. Use `--backfill` before the first successful crash poll to include historical crashes, including after upgrading the listener.

### Setup checks and agent-readable status

After configuring `apps.json`, run these from the repository root:

```sh
listener/bug-listener doctor --json  # check config, tools, devices and tracker access
listener/bug-listener status --json  # read last poll, health and pending evidence
```

These commands need no feature flag. Run the listener at least once to populate status; keep it running for current results. `status` only reads local state. Omit `--json` for human-readable output. See [health checks and exit codes](docs/ops/listener.md).

### Other reporting features

| Feature | How to enable or configure it |
|---|---|
| Shake and keyboard reporting | Enabled by `.bugReporting(reporter)`. `systemShake`, `gentleShake`, `commandI` and `dialogKeys` default to `true`. |
| Report button | Add `BugReportButton(reporter: reporter)` to your view or toolbar. |
| Session log association | Create `SessionLog`, then supply `sessionLog: { log.position }`, `logger: log.logger` and `flushLog: { log.flush() }` hooks as in the quick start. |
| Copy the log into each report | Set `options.copySessionLog = true` with the session-log hooks above; adds `session.jsonl`. Default: `false`. |
| Standalone report metadata | Set `options.writeReportJSON = true` to add `report.json` beside attachments. Default: `false`; the main `bugs.jsonl` index is always written. |
| Dictate a note | Add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` to Info.plist, then set `options.dictation = true`. Default: `false`. |
| Fresh evidence for “Log it and another” | Set `options.another = .recapture`. The default `.keepMoment` reuses the captured screenshot and diagnostics. |
| App context and extra attachments | Supply the `context` and `extraFiles` hooks; see the [integration example](docs/integration.md). |
| Commit in reports | Set `BugKitCommit` in the app's Info.plist to its build's git commit. |
| Simulator launch hooks | Set `options.launchHookPrefix = "APP"` and call `reporter.runLaunchHooks()` on appearance. Launch with `SIMCTL_CHILD_APP_BUG="test note" xcrun simctl launch booted <bundle-id>` to save a report, or use `SIMCTL_CHILD_APP_SHAKE_AFTER=2` to open the dialog. |
| What's new | Add the `scripts/whats-new.sh` build phase, load `WhatsNewSeen.bundledFeed()`, then display `WhatsNewRow` / `WhatsNewView`; see the [complete setup](docs/integration.md). |
| Log retention | Call `BugStore().pruneLogs(logger: log.logger)` at launch to prune logs older than 30 days while retaining reported logs. |

## Pull and file reports

The listener needs [uv](https://docs.astral.sh/uv/), Xcode’s `devicectl`, and paired devices. GitHub trackers also need authenticated `gh`; beads trackers need `bd`.

From the repository root:

```sh
mkdir -p ~/.config/bug-kit ~/tmp/agent/bugs
cp listener/apps.example.json ~/.config/bug-kit/apps.json
# Edit apps.json: app name, bundle ID, local repo and tracker.
listener/bug-listener doctor --json
listener/bug-listener --once --dry-run --backfill
listener/bug-listener --once --backfill
listener/bug-listener
# From another terminal:
listener/bug-listener status --json
```

**First contact matters:** without `--backfill`, the listener marks existing reports and crash files seen without filing them. The two streams have separate baselines, including when upgrading from a listener that did not discover crashes. Use `--backfill` on the first real poll to file existing evidence. A dry run copies files and writes logs, but leaves issues, seen-store, inbox and notifications unchanged.

Crash files are discovered on every poll, even without a manual report. Signal/exception crashes include the latest preceding session log when its start time is available; that association is explicitly marked as inferred. MetricKit payloads keep their crash/hang evidence without claiming an exact session.

Reports land under `~/tmp/agent/bugs/<app>/<device>/`. Failed copies of a report’s folder or named session log leave it pending for the next poll. Screenshots stay on the Mac; issue bodies contain their local paths.

See [listener setup](docs/ops/listener.md) for configuration, logging and launchd. For manual pulls and deployment:

```sh
scripts/pull-reports.sh                       # all configured apps and devices
scripts/pull-reports.sh --check               # exit 1 for unfiled reports; 2 for lookup errors
scripts/deploy-all.sh my-app --dry-run        # inspect the configured deployment commands
```

## Documentation

| Guide | Contents |
|---|---|
| [Integration](docs/integration.md) | Hooks, options, session logs, dictation and What's new |
| [Report format](docs/report-format.md) | JSON Lines keys and Documents layout |
| [Principles](docs/principles.md) | Evidence, reporting, deduplication, crashes and debugging practices |
| [App migrations](docs/migration.md) | Historical feature matrix and EA, CG and MM migration checklists |
| [User stories](docs/stories/README.md) | Acceptance criteria and verification rungs |
| [Operations](docs/ops/README.md) | Pulling, filing, signing, deployment, runners and simulators |

## Where a bug gets fixed

**A bug in BugKit's code is fixed in BugKit, not in the app.** That covers the dialog, shake, dictation, the store
and its format, crash capture, pruning, What's new, the listener and the scripts. Every app shares one copy, so a
patch inside one app leaves the others broken and the copies drift apart, which is how three apps ended up with
three bug-report implementations.

1. File the issue here (idvorkin/bug-kit), quoting the app's report and log line. The app's issue links to it.
2. Fix it on a branch here, with a host test that fails before the fix. This is a public repo, so leave out
   personal data.
3. PR and merge, then bump the BugKit version in each app (its SPM reference) and redeploy.
4. Until the fix lands, an app may work around it through BugKit's hooks or options, never by copying BugKit's
   code in. Mark the workaround with a `ponytail:` comment naming the BugKit issue.

Example: Context Grabber's dictation reset (CG #249) was fixed here as PR #3, then picked up by each app.

A bug in the app's own hooks (its context, screen names, extra files, logger bridge) stays in the app.

## Developing BugKit

### no-mistakes validation

This repo uses [.no-mistakes.yaml](.no-mistakes.yaml) for targeted local validation and [.github/workflows/ci.yml](.github/workflows/ci.yml) for the full Swift/Python regression suite and iOS compilation on macOS. The local Test agent selects checks relevant to the change; simulator diagnostics are available for UI changes.

On a new checkout, with `no-mistakes` installed and a supported agent configured:

```sh
no-mistakes init
no-mistakes doctor
# Commit the intended changes on a feature branch, then:
no-mistakes axi
no-mistakes axi run --intent "Describe the user's goal and constraints"
```

The run performs review, validation, documentation, push, PR creation and CI monitoring. Resolve any decision gates through `no-mistakes axi respond`; `no-mistakes axi status` shows progress. The repository's custom gate commands and instructions take effect after `.no-mistakes.yaml` is merged into the default branch. Initializing the local gate alone does not publish changes or configure GitHub branch protection.

### Manual checks

On a Mac with Swift 6+, uv and `jq` (used by the shell scripts):

```sh
swift test
uv run --with typer --with pytest pytest listener/ Tests/scripts/
for script in scripts/*.sh; do bash -n "$script"; done
```

Swift tests cover storage, concurrent writes, report flow, dictation merging, logs, crashes and What's new. Python tests cover listener parsing, deduplication, independent crash discovery, evidence retries, doctor/status JSON and deployment commands with fake tools.

With XcodeGen and a selected iOS simulator, run `scripts/test-ios-diagnostics.sh <simulator-udid>` to check accessibility redaction, traversal limits and control capture.

Host tests do not exercise the iOS UI. Typecheck it with an installed iOS SDK:

```sh
xcrun --sdk iphoneos swiftc -typecheck -swift-version 6 -target arm64-apple-ios17.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" Sources/BugKit/*.swift
```

For device verification, shake, save with “Log it and another,” then save a second note. Confirm the listener receives two reports with their evidence. Record whether a fix was verified on the host, in a simulator or on a device; see the [test ladder](docs/ops/test-ladder.md).
