# App migrations

[Back to BugKit](../README.md). The feature matrix is a historical snapshot from 2026-10-10; use each app’s current checkout when migrating.

"✓" means the app had the feature on its origin/main of 2026-10-10; "–" means it does not. The BugKit column gives the option or type that provides the feature.

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
