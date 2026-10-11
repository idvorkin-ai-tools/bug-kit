# App migrations

[Back to BugKit](../README.md). The feature matrix below is a historical snapshot; the adoption guide describes the combined PR #4/#8/#9/#10/#11/#12 release. Downstream observations were read from local checkouts on 2026-10-10 and may differ from their current remote branches. These instructions do not mean those repos have already been updated or validated.

## Adopting the merged features

First update the app's BugKit package resolution to a `main` commit containing all six feature PRs. Refresh and commit each app's tracked `Package.resolved` after resolving; a `branch: main` declaration alone does not refresh a pinned revision. Xcode apps can use **File → Packages → Update to Latest Package Versions**; Swift packages can run `swift package update bug-kit`. Keep any required feature enabled explicitly in the app's integration code.

The Mac listener and shell scripts come from the BugKit checkout used by your agent or launchd job, which may differ from the app's SPM checkout. Update that checkout too, restart the listener, then run `listener/bug-listener doctor --json`. Existing report formats remain readable. New automatic reports need the updated listener for their title, reason and labels.

| PR | What changes in consuming repos | Dependency and verification |
|---|---|---|
| #4: pruning, JSON bridge, macOS What's new | Replace local JSON conversion helpers with `JSONValue.foundation`; optionally use `pruneLogs(keepNewest: 20)` and shared macOS What's new views. | Refresh package before removing helpers. Verify logs referenced by reports survive pruning and the Mac views open. |
| #8: clocks, memory, log tools | For BugKit's logger, opt into `SessionLog(prefix: "app", clocks: [.wall, .mono])` and `log.status(every: 5, memory: true) { ... }`. Apps retaining their own logger need equivalent fields before using wall-time slicing. Point log recipes at `scripts/log-tool.sh`. | Defaults remain unchanged. Check `wall`, `mono`, `rss_mb` and a known timestamp slice. Keep `session_start.started` with a timezone for listener crash-session inference. |
| #9: copyable errors, model and commit | BugKit's dictation errors become copyable by default (`copyableErrors = false` opts out). App-owned error views can adopt `BugProblem`/`BugProblemView`. Remove equivalent device-model workarounds. Pass the app's commit as described below. | Test a denied microphone/error path, pasted context/build, Mac model and a dirty build. |
| #10: device tools | Point monitoring/symbolication recipes at `bugs-monitor.sh` and `symbolicate.sh`. Add optional `pull_extra` paths to the Mac's apps config. Save logs/buffers before relaunching. | #8 supplies the log-tool/clock conventions. Check monitor failure/recovery and symbolication with both matching and wrong-build dSYMs. `pull_extra` belongs to `pull-reports.sh`, not automatic listener polling. |
| #11: simulator smoke helpers | Source `scripts/smoke-lib.sh` from each app's smoke script; retain app-specific launch hooks, fixtures and expected events. | Needs Bash and jq. Verify launch freshness, timeout failure, error events and stash restoration, including interruption. |
| #12: automatic reports | Call `reporter.autoReport(reason: "call_failed", context: ..., files: [callLog])` from an app-owned failure trigger. Configure `options.auto.window` and `options.auto.maxBytes` before creating the reporter. | Default window: 600 seconds per reason; copied-file budget: 5 MB. Keep one reporter, provide `flushLog`, and use stable reason codes. Test repeat triggers, relaunch, oversized logs and listener delivery before retiring existing delivery. |

### Exercise Analyzer

Observed integration: `ExerciseAnalyzer/BugReport.swift` imports BugKit, adapts EA's logger and still declares a local `extension JSONValue { var foundation: Any ... }`.

1. Update its BugKit resolution, then remove the local `foundation` extension in that file; the existing `fields.mapValues(\.foundation)` bridge can use the shared property. Keep EA's own `SessionLog`, context and frame-at-playhead hook.
2. Preserve `gentleShake = false` and `.keepMoment`. These are deliberate exercise-app choices, not migration omissions. Keep the speech/microphone usage strings for its enabled dictation.
3. If enabling the earlier UI diagnostics, set `recordInteractions` and `captureAccessibility` on these same options, and provide stable accessibility identifiers and semantic action hooks. Add a `flushLog` hook if the app's logger buffers writes.
4. Route its log inspection and symbolication recipes to the shared tools after comparing results on an existing fixture. `pull_extra` can name its WatchConnectivity inbox using the real path under the container; do not substitute a guessed folder.
5. Before a rebuild/relaunch recipe terminates the app, pull the latest session log and relevant rolling evidence. Preserve the app's signing lock and Watch installation behavior.
6. Verify host tests, then the app's `SWING_BUG`/`SWING_SHAKE_AFTER` simulator checks, copied dictation errors and report frame. The historical PR #246 checklist below records earlier adoption; it is not proof these new options are enabled.

### Magic Monitor

Observed integration: `Package.swift` pins `feat/mm-bridge-and-cap` with a ponytail comment. `Sources/MagicMonitor/SessionLog.swift` already calls `pruneLogs(keepNewest: 20)` and supplies the logger bridge. `Sources/MagicMonitor/AppModel.swift` contains a `hw.model` workaround for BugKit issue #6.

1. Change the BugKit dependency from `branch: "feat/mm-bridge-and-cap"` to `branch: "main"`, resolve the merged revision and remove that temporary branch comment. Check the iPad's package resolution separately.
2. Keep the current count cap and custom logger; those calls now have support on main. Keep `BugStore(documents: Self.root)` so Mac evidence stays in MM's chosen directory.
3. Replace the app's issue-#6 hardware-model workaround with `BugAppInfo.hardwareModel()` after checking the reported model. Use the shared `WhatsNewRow`/`WhatsNewView` where appropriate, while retaining app-specific presentation and its Mac report sheet.
4. MM's logger already has its own timing conventions. Do not introduce a second session logger just to get #8. Check shared `log-tool.sh around` against MM's existing wall-time lines before switching recipes.
5. Preserve `just run`'s evidence capture before relaunch. Keep Mac report filing local; the listener discovers paired iOS devices, not the Mac app's container. `BugReporter` and passive UIKit capture are iOS-only; a Mac automatic reporter can use `BugAutoReporter(writer: ...)` with its existing writer.
6. Verify `just test`, Mac `just selftest`, and `just ipad-selftest` for iPad integration changes. Hardware camera behavior and permission prompts require a separate device check.

### Context Grabber

The inspected checkout still has its own `native/App/BugReport.swift` sheet and no BugKit dependency in `native/project.yml`/`native/ContextCore/Package.swift`. Confirm the actual branch before applying this sequence; PR #12's planned gist replacement does not itself change CG.

1. Add/update BugKit in the app's XcodeGen package dependencies. Migrate the report UI using [the integration hooks](integration.md), preserving CG's `.recapture`, gentle shake, microphone-busy hook, app context, screen names and `GRABBER` launch prefix. Keep speech and microphone Info.plist descriptions.
2. Replace duplicated reporter/dictation/pruning helpers only after their call sites use BugKit. App-specific errors can use `BugProblem`/`BugProblemView`; keep app-owned failure detection in CG.
3. Wire the actual failed-call/diagnostics path to `reporter.autoReport(reason: "call_failed", context: ["stage": .string(stage)], files: [callLog])`. Supply a logger flush hook so the file includes the failure. Use a stable reason, not a call ID, or every call bypasses the per-reason window.
4. Replace the diagnostics gist upload path only after local report creation and listener delivery pass. Remove gist-only credentials and cleanup code only when no other feature uses them. Delivery now waits for the Mac to reach the device; it is not an immediate remote upload or an acknowledgement of issue creation.
5. Replace the outdated monitor wrapper with `scripts/bugs-monitor.sh context-grabber`; check its `check_failed`/`check_ok` recovery behavior. Move generic simulator plumbing to smoke-lib while keeping CG fixtures and import hooks.
6. Verify one failed-call fixture, a second trigger inside the window, relaunch suppression, a large log, offline-device recovery and one listener-filed automatic report using fake tracker tools. A real failed phone call remains a downstream validation step, not evidence established by merging BugKit.

### Shared build and tool recipes

Set `BugKitCommit` in the app Info.plist to `$(BUGKIT_COMMIT)` and pass the app checkout's value to both simulator and device builds:

```sh
xcodebuild ... BUGKIT_COMMIT="$(git describe --always --dirty --exclude='*')" build
```

For `deploy-all.sh`, add `"BUGKIT_COMMIT={describe}"` to that app's `build.settings`. This describes the app checkout, not BugKit's commit. Keep a missing setting honest as `unknown`. The What's new build phase needs access to git history and the output bundle; the existing recipe uses `ENABLE_USER_SCRIPT_SANDBOXING: NO` for that target.

```sh
"$BUG_KIT/scripts/log-tool.sh" around "$LOG" 15:10:00 10
"$BUG_KIT/scripts/log-tool.sh" at "$LOG" 84442 10
"$BUG_KIT/scripts/symbolicate.sh" "$CRASH_JSON" "$DSYM_DIRECTORY"
"$BUG_KIT/scripts/bugs-monitor.sh" exercise-analyzer
```

`BUG_KIT`, `LOG`, `CRASH_JSON` and `DSYM_DIRECTORY` are paths chosen by the app's recipes. Preserve build dSYMs: symbolication deliberately refuses a different binary UUID. Keep the event catalogue and each story's `Issues:`/`Status:` entries updated alongside the app changes.

## Historical feature matrix and migration checklists

"✓" means the app had the feature on its origin/main of 2026-10-10 (EA after PR #246 that evening); "–" means it does not. The BugKit column gives the option or type that provides the feature.

| Feature | EA | CG | MM | BugKit |
|---|---|---|---|---|
| iOS shake gesture opens the report | ✓ | ✓ | – | `systemShake` (on) |
| Gentle shake read from motion (CG story 146) | – | ✓ | – | `gentleShake` (on) |
| A button | ✓ | ✓ | ✓ (iPad Settings) | `BugReportButton` |
| ⌘I | ✓ | – | ✓ | `commandI` (on) |
| Return/Escape keys in the dialog | ✓ | – | ✓ | `dialogKeys` (on) |
| Screenshot taken before the dialog | ✓ | ✓ | – (video instead) | always |
| Opens over other sheets (topmost VC) | ✓ (#41) | ✓ (#182) | – | always |
| "Log it and another" | ✓ keeps the moment | ✓ re-captures | ✓ | `another: .keepMoment` or `.recapture` |
| Speak the note (CG #239) | – | ✓ | – | `dictation` (off: needs Info.plist strings) |
| "Nothing leaves this iPad" | – | – | ✓ | `privacyNote` |
| A report `id` (UUID) and ms `reported_at` | ✓ | – | – | always |
| Locked index append (mmn-cfr) | ✓ | – | ✓ | always |
| Unique folders within one second | ✓ | – | ✓ | always |
| Report names its log and the moment | ✓ | ✓ | ✓ (copies the log) | `log`, `session_t_ms`; `copySessionLog` |
| Build and commit in the report | ✓ | ✓ | ✓ | always (`BugKitCommit`) |
| Typed context (numbers stay numbers) | ✓ | – (strings) | ✓ (Codable) | `context: [String: JSONValue]` |
| Extra files: clip, recent segments, report.json | ✓ frame | – | ✓ | `extraFiles`, `RecentSegments`, `writeReportJSON` |
| JSON Lines session log per launch | ✓ | ✓ | ✓ | `SessionLog` (optional) |
| Periodic status line helper | ad hoc | ad hoc | ad hoc | `SessionLog.status(every:)` |
| Logs pruned at 30 days, reported ones kept | ✓ | ✓ | – | `BugStore.pruneLogs` |
| MetricKit, signal and exception files, announced once | ✓ | ✓ | – | `CrashReports` |
| Simulator hooks for reports | ✓ `SWING_BUG` | ✓ `GRABBER_BUG` | selftest script | `launchHookPrefix` |
| What's new from git and the stories (CG story 148) | ✓ | ✓ | – | `WhatsNew`, `WhatsNewView`, `WhatsNewRow`, `scripts/whats-new.sh` |
| Pull from the phone **and** the iPad | ✓ (`bugs-check` through `pull-reports.sh --check`; `pull-logs` is still per device) | ✓ (PR #241) | – | `scripts/pull-reports.sh` |
| File each report once | ✓ GitHub, paths named | ✓ GitHub, no images | ✓ beads | `listener/bug-listener` (GitHub, beads, none) |
| Always-on listener, inbox and notification | – | – | – | `listener/bug-listener` |
| Deploy to every device under the signing lock | – | – | ✓ lock (iPad only) | `scripts/deploy-all.sh` |

### Migration checklists

The order is EA first (CG's copy came from it), then CG, then MM. Each app keeps its own context, screen names and stories. One commit per step.

**Exercise Analyzer** (done 2026-10-10, EA PR #246: steps 1–6 as written, 7 left to the lock by hand; `gentleShake` off by choice, since a kettlebell phone travels between sets; EA keeps its own `SessionLog` behind a 12-line `JSONValue` → `Any` bridge)
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
