# The evidence: report, log and crashes

Part of the [BugKit stories](README.md).

---

### User Story 010:

- **Summary:** One report format in every app (technical)
- **From:** the bug-kit proposal; EA and CG `bugs.jsonl`; MM `report.json`
- **Issues:** #6
- **Status:** `BugReport` and `BugStore`, verified on the host by:
  - `reportRoundTripsThroughItsLine`;
  - `lineUsesTheFixedSnakeCaseKeys`, which also checks that a note with a newline stays one line;
  - `reportedAtKeepsMillisecondsAndReadsTheOlderWholeSecondForm`;
  - `readAllCountsLinesItCannotRead`;
  - the `device` model by `DeviceModelTests` (bug-kit#6, from MM): a Mac reads `hw.model`, not "arm64". A device
    still has not checked it;
  - `commit` from a build with uncommitted changes ends in `-dirty`: the `BUGKIT_COMMIT` recipe in the README and
    `deploy-all.sh`'s `{describe}`, verified on the host by `scripts/tests/test_deploy_all.py` (dry run). An app
    build reading it back is a device check, still to do.

#### Use Case:
- **As the** listener, or an agent filing reports from any app
- **I want to** read one format: fixed fields, an `id`, and the app's own `context`
- **so that** one filer serves every app, and no report is keyed on a timestamp two reports can share

#### Acceptance Criteria:
- **Scenario:** A report on disk
- **Given:** a report is saved
- **Then:**
  - its line has `id`, `reported_at` (ms, UTC), `app`, `bundle`, `build`, `commit`, `device`, `screen`, `note`, `log`, `session_t_ms`, `screenshot`, `folder`, `files` and `context`;
  - a raw newline in the note is escaped, so the line is one valid JSON line.

- **Scenario:** The device names its model
- **Given:** a report is saved on a phone, a Mac or a simulator
- **Then:** `device` starts with the model: "iPhone18,1" on a phone, "Mac16,12" on a Mac (not the CPU's "arm64"),
  and the simulated model on a simulator. It never holds the device's own name.

- **Scenario:** A build from uncommitted changes
- **Given:** the app was built with `BUGKIT_COMMIT` from `git describe --always --dirty` while the tree had changes
- **Then:** `commit` reads `abc1234-dirty`, never the clean commit's `abc1234`.

- **Scenario:** An older line
- **Given:** `bugs.jsonl` also holds an older app's line, or a torn one
- **Then:** reading skips it and counts it, and the listener logs it as `line_unreadable`. It is never fatal.

---

### User Story 011:

- **Summary:** Every launch keeps a log (technical)
- **From:** CG story 141; EA DEBUGGING.md
- **Status:** `SessionLog`, verified on the host by `sessionLogWritesOneLinePerEventWithTypeAndT` and `twoLogsInOneSecondGetTheirOwnFiles`.
  - It is optional: an app with its own log passes its logger.
  - Wall and host-clock stamps (MM's special sauce): `SessionLog(clocks: [.wall, .mono])` and
    `SessionLog.wall(ofMono:)`, verified on the host by `linesCarryWallAndMonoWhenAsked`, `noClocksByDefault`,
    `wallStampsKeepTheLocalOffsetAndMilliseconds` and `aFramesHostTimeConvertsToWallTime`.

#### Use Case:
- **As a** developer asked "why did it do that"
- **I want to** read what the app did in that launch, with numbers
- **so that** a symptom is explained from evidence instead of a theory

#### Acceptance Criteria:
- **Scenario:** A launch
- **Given:** the app creates `SessionLog(prefix: "app", fields: [device, system, build])`
- **Then:**
  - a new `Documents/logs/app-<stamp>.jsonl` exists;
  - its first line is `session_start` with those fields;
  - every later line has `type` and `t` (ms since launch), which a field cannot overwrite;
  - a NaN becomes null instead of losing the line.

- **Scenario:** "It just happened at 15:10"
- **Given:** the app opened its log with `clocks: [.wall, .mono]`
- **When:** someone says when a problem happened, or a camera frame's host time is known
- **Then:**
  - every line also has `wall` (local time with milliseconds and the zone offset) and `mono` (host-clock seconds),
    neither of which a field can overwrite;
  - `SessionLog.wall(ofMono:)` turns a frame's or a segment's host time into the wall time a person would name;
  - `scripts/log-tool.sh around 15:10:00 10` slices the log to that moment.

---

### User Story 012:

- **Summary:** A status line every few seconds (technical)
- **From:** device-debug-loop; EA `clock` (#23), `sync_status` (#231); CG `call_out_level` (#186)
- **Status:** `SessionLog.status(every:)`, verified on the host by `theStatusLineRepeats`.
  - `memory: true` adds `rss_mb` (MM's special sauce), verified on the host by `residentMemoryIsReadable` and
    `theStatusLineCarriesRSSWhenAsked`.

#### Use Case:
- **As a** developer reading a report about something that went quiet
- **I want to** see the state every few seconds before the report
- **so that** I know when the problem started, not only when it was noticed

#### Acceptance Criteria:
- **Scenario:** A stuck pass
- **Given:** `log.status(every: 5) { [...] }`
- **Then:** the log has a `status` line every 5 s with those fields, until the app ends

- **Scenario:** A leak, or the memory limit
- **Given:** `log.status(every: 5, memory: true) { [...] }`
- **Then:** each status line also has `rss_mb`, so a climb before a kill with no crash file is in the log

---

### User Story 013:

- **Summary:** Old logs do not pile up, reported ones stay (technical)
- **From:** EA #72 (story 036); CG story 145
- **Status:** `LogRetention` and `BugStore.pruneLogs`, verified on the host by:
  - `oldLogsGoExceptOnesAReportNames`;
  - `pruningLogsALineEvenWhenNothingGoes`;
  - `anUnreadableIndexPrunesNothing`;
  - `retentionKeepsTheBoundary`.

#### Use Case:
- **As someone** whose storage is not for log files
- **I want to** have logs older than thirty days deleted
- **so that** the footprint stays small while the evidence for an open report survives

#### Acceptance Criteria:
- **Scenario:** A launch with old logs
- **Given:** a 40-day-old log no report names, and two 40-day-old logs that reports name (one by `logs/` path, one by bare name)
- **When:** the app calls `pruneLogs` at launch
- **Then:**
  - the first log is deleted and the other two are kept;
  - the log has one `logs_pruned` line with count 1, the bytes, and `kept_for_reports` 2.

- **Scenario:** An index it cannot read
- **Given:** `bugs.jsonl` exists but cannot be read
- **Then:** nothing is deleted, and the log has an `error` saying so

---

### User Story 014:

- **Summary:** The report carries what the app adds: a clip, recent video, the log itself
- **From:** EA story 026 (the frame at the playhead); MM story 040 (the last 90 s of segments, `session.jsonl`, `report.json`)
- **Status:**
  - The `extraFiles` hook is verified on the host by `writerSavesTheScreenshotTheExtraFilesTheLineAndTellsTheLogger` and `aFailingExtraFilesHookIsLoggedAndTheReportStillSaves`.
  - `RecentSegments.covering` is verified on the host by `recentSegmentsCoverTheLastNinetySeconds`.
  - `copySessionLog` and `writeReportJSON` are verified on the host by `writerCopiesTheSessionLogAndWritesReportJSONWhenAsked` and `aMissingSessionLogIsAnErrorAndTheReportStillSaves`.

#### Use Case:
- **As a** developer fixing a replay or a camera bug
- **I want to** have the video and the log of the moment inside the report's folder
- **so that** nothing rolls off or is pruned before I look

#### Acceptance Criteria:
- **Scenario:** Recent segments
- **Given:** the app records in 5 s segments and reports at 148 s
- **When:** its `extraFiles` hook copies `RecentSegments.covering(…, seconds: 90)`
- **Then:**
  - the folder holds the segments from 55 s to 150 s;
  - `files` names them.

- **Scenario:** A hook that fails
- **Given:** the hook throws
- **Then:** the report is still saved without those files, and the log has `error` where `bug_extra_files`

---

### User Story 015:

- **Summary:** A crash comes back with the logs (technical)
- **From:** EA story 036, #87; CG story 144, 509da33
- **Status:**
  - `CrashReports`. The announce-once is verified on the host by `crashFilesAreAnnouncedOnceThenRenamed`.
  - The MetricKit subscriber and the signal and exception handlers are verified by typecheck and build.
  - `scripts/symbolicate.sh` (EA's, generalized). It is verified on the host by `scripts/tests/test_symbolicate.py`
    against a real arm64 binary and its dSYM. That test found that the older `atos -l 0x0` recipe never resolved.
  - A real crash in a BugKit app is still to come.

#### Use Case:
- **As a** developer reading a session log that stops mid-work
- **I want to** get the crash's reason and stack with the same pull as the logs
- **so that** a crash is diagnosed from evidence like any other report

#### Acceptance Criteria:
- **Scenario:** The launch after a crash
- **Given:** the app crashed
- **When:** it is opened again
- **Then:**
  - the log has one `crash_report` naming a file under `crashes/`: kind signal or exception, with its first lines as `top`, or kind crash or hang from MetricKit;
  - the file is pulled with the logs;
  - a later launch does not announce it again.

- **Scenario:** An exception, then the abort
- **Given:** an Objective-C exception aborts the app
- **Then:**
  - `crashes/` holds one `exception-<epoch>.txt` and no second `signal-` file;
  - the crash still reaches the system's own report.

---

### User Story 016:

- **Summary:** A hang names itself (technical)
- **From:** EA #231 (0x8BADF00D on the iPad from synchronous FileProvider calls in the iCloud sync), EA #86
- **Status:** `CrashReports` logs MetricKit hangs as `crash_report` kind hang, with `seconds`. Verified by typecheck. A real hang is still to come.

#### Use Case:
- **As a** developer whose app the watchdog killed
- **I want to** see a hang in the log with its length and its payload's stacks
- **so that** I find the main-thread call that blocked, instead of guessing

#### Acceptance Criteria:
- **Scenario:** A hang
- **Given:** MetricKit delivers a hang diagnostic
- **Then:** `crashes/<stamp>.json` holds it, and the log has `crash_report` kind hang with the seconds

---

### User Story 017:

- **Summary:** A report carries recent interactions and the app's accessibility metadata
- **From:** BugKit agent debugging workflow, 2026-10-10
- **Status:** Host tests verify bounded JSON Lines, frozen evidence and independent attachment failures. Five diagnostic tests passed on the iOS 27 simulator, including redaction, traversal limits, cyclic accessibility containers, control-action capture and detachment. Physical touch/gesture behavior still needs verification in a consuming app.

#### Acceptance Criteria:
- Opt-in interaction capture logs touch sequences, UIKit actions, scene activity and explicit semantic actions.
- Before the report UI opens, recent breadcrumbs and public view/accessibility metadata are frozen with the screenshot.
- The files are named in the index and preserved alongside the app's own attachments.
- Capturing does not cancel/delay touches or replace app control handlers.
- Structured capture excludes text-entry values/subtrees, bounds the tree/buffer and describes incomplete SwiftUI AX coverage.
- Agent-specific semantic actions can be logged directly by identifier.
