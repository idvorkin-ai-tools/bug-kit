# Integrating BugKit

[Back to BugKit](../README.md).

1. Add the package. In Xcode, use **File › Add Package Dependencies** with `https://github.com/idvorkin/bug-kit`.
   With XcodeGen, add this to `project.yml`:

   ```yaml
   packages:
     BugKit: { url: https://github.com/idvorkin/bug-kit, branch: main }
   targets:
     MyApp:
       dependencies: [{ package: BugKit }]
   ```

2. Set Info.plist `BugKitCommit: $(BUGKIT_COMMIT)` and pass the app's commit on the build command:
   `xcodebuild ... BUGKIT_COMMIT="$(git describe --always --dirty --exclude='*')" build`.
   This marks uncommitted builds `-dirty`. `deploy-all.sh` supports `"BUGKIT_COMMIT={describe}"` in
   `build.settings`. Without a supplied value, reports say "unknown".

3. At launch:
   - open the session log, if the app has none of its own;
   - install crash capture;
   - prune old logs;
   - create one reporter with the app's hooks and options, and attach it to the root view.

The example below uses your app’s `AppModel` and `ContentView`; adapt the hooks to your model.

```swift
import BugKit
import SwiftUI

@main
struct MyApp: App {
  @StateObject private var model: AppModel
  @StateObject private var reporter: BugReporter
  let log: SessionLog
  let whatsNew = WhatsNewSeen.bundledFeed()                            // whats-new.json from scripts/whats-new.sh

  init() {
    let log = SessionLog(prefix: "app", fields: ["build": "1.0 (42)"])
    self.log = log
    CrashReports.shared.install(logger: log.logger)        // MetricKit, signal and exception files, announced once
    BugStore().pruneLogs(logger: log.logger)               // logs older than 30 days, except reported ones
    let model = AppModel(log: log)
    _model = StateObject(wrappedValue: model)
    var options = BugReporterOptions()
    options.another = .keepMoment                          // or .recapture: a fresh picture for each report
    options.dictation = true                               // needs the speech and microphone usage strings
    options.privacyNote = "Nothing leaves this device until the developer pulls it."
    options.launchHookPrefix = "APP"                       // SIMCTL_CHILD_APP_BUG="a|b" in simulator checks
    _reporter = StateObject(wrappedValue: BugReporter(hooks: BugReporterHooks(
      screen: { model.screenName },                              // "home", "playback"
      context: { ["exercise": .string(model.exercise), "playhead": .double(model.playhead)] },
      sessionLog: { [log] in log.position },                     // ("logs/app-20261010-150000.jsonl", 84442)
      logger: log.logger,                                        // bug_report lands in the session log
      extraFiles: { folder in                                    // optional: e.g. the clip at the playhead
        try await model.exportClip(to: folder.appendingPathComponent("clip.mov"))
        // Window snapshots can omit video layers; render the playhead frame from the clip.
        try await model.writeFrame(to: folder.appendingPathComponent("frame.jpg"))
        return ["clip.mov", "frame.jpg"]
      },
      microphoneBusy: { model.inCall },
      flushLog: { log.flush() }), options: options))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .bugReporting(reporter)  // shake (hard or gentle), or ⌘I on a hardware keyboard
        .onAppear { reporter.runLaunchHooks() }
    }
  }
}

// Anywhere a button is easier than a shake (an iPad on a stand):
BugReportButton(reporter: reporter)
// The home screen's What's new line, with its ✕, and the list it opens:
WhatsNewRow(feed: whatsNew, logger: log.logger) { showWhatsNew = true }
NavigationStack { WhatsNewView(feed: whatsNew, logger: log.logger) }
```

- `reporter.shakeEnabled = false` ignores shakes, for example during a run where the phone is in a pocket (EA
  story 037).
- `reporter.lastStatus` says "Problem logged. Thanks." after a save, for a status line.
- `log.status(every: 5) { [...] }` writes a periodic status line.
- Add `memory: true` to include resident memory (`rss_mb`); create the logger with `clocks: [.wall, .mono]`
  to include wall-clock and host-uptime timestamps. See [logging conventions](ops/logging.md).
- For an app-owned `[String: Any]` logger, use `{ type, fields in log.event(type, fields.mapValues(\.foundation)) }`.
- `WhatsNewRow` and `WhatsNewView` also build on macOS. The UIKit reporter remains iOS-only.
- `RecentSegments.covering(segments, now:, seconds: 90, start:, end:)` picks the recorded segments for `extraFiles`.

For dictation, add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` to Info.plist before setting `dictation = true`.

4. **What's new** is a build phase. With XcodeGen:

   ```yaml
   preBuildScripts:
     - name: What's new
       script: '"$BUILD_DIR/../../SourcePackages/checkouts/bug-kit/scripts/whats-new.sh" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/whats-new.json" --repo "$SRCROOT" --base-url "https://github.com/<owner>/<repo>/blob/main/docs/stories/"'
       basedOnDependencyAnalysis: false
   ```

   - It reads the last 30 days of `git log` and the stories in `docs/stories/`, in the "### User Story NNN:" and
     "- **Summary:**" form.
   - A commit counts when its subject starts with "Story NNN:", ends with "(story NNN)", names the story in its
     message, or names an issue that a story's Issues line lists.
   - Without git history it writes an empty feed and never fails the build.
   - The phase reads `.git` and writes into the bundle; the existing recipe sets
     `ENABLE_USER_SCRIPT_SANDBOXING: NO` on the app target.

## Automatic reports

Keep one reporter and invoke the failure hook only when the app's own check identifies a problem:

```swift
var options = BugReporterOptions()
options.auto.window = 600
options.auto.maxBytes = 5_000_000
// Pass options and flushLog to BugReporter at construction, then at a failure:
reporter.autoReport(reason: "call_failed", context: ["stage": .string("transcribe")], files: [callLog])
```

`autoReport` flushes the app's log hook, captures screen/log position, and schedules a save without a dialog or
screenshot. It does not await delivery. The saved report carries `source: "auto"` and `reason`; manual reports
omit both keys. A persistent per-reason window limits repeat triggers across relaunches. Use stable reason codes
so unique call IDs do not defeat the limit. Attachments share the configured byte budget, including
`session.jsonl` when `copySessionLog` is on (copied once, even if also passed in `files`); `report.json` and the
bugs.jsonl line are outside it. Oversized text logs keep their tail from a line start (`bug_report_auto_cut`); a
file that fails is logged as an `error` (`bug_auto_file`) and the rest are still attached; files with the same name
are kept as `call.jsonl`, `call-2.jsonl`. Manual reports still copy the whole session log. A Mac or Foundation-only caller can retain `BugAutoReporter(writer:options:)` and await
`report(reason:context:files:)`; provide its own logger flush before calling.

The updated Mac listener files an automatic report with a reason-based title and `bug,auto` labels (beads:
`from-app,auto`), deduplicated by report ID. If GitHub labels do not exist, filing retries without labels.
Delivery waits for a reachable device. Automatic reports do not implicitly capture the manual report's
interaction/accessibility snapshot; the manual diagnostic options below remain independent.

See [per-app adoption](migration.md#adopting-the-merged-features) before replacing a diagnostics gist or removing
an app's existing delivery path.

## Interaction and accessibility diagnostics

Enable the options when constructing the reporter:

```swift
var options = BugReporterOptions()
options.recordInteractions = true
options.captureAccessibility = true
options.interactionLimit = 200  // 1...1,000 events retained per report
```

Pass `options` to `BugReporter(hooks:options:)` and attach `.bugReporting(reporter)` to the app's root view. Both options default to false. Interaction events go to the existing logger and a bounded in-memory buffer. At report opening, BugKit freezes the buffer and the accessibility snapshot alongside the screenshot. `.keepMoment` reports reuse this evidence; `.recapture` takes a fresh snapshot. The report's log position now names the captured moment rather than the later save time.

The report folder gains `interactions.jsonl` and `accessibility.json`, also listed in the report's `files`. These files are independent of the app's `extraFiles` hook. Their contents stay local when the listener files an issue; the issue lists their paths.

| Event | Evidence |
|---|---|
| `ui_touch_begin` | Original hit view's class, nearest accessibility identifier, coordinates and touch type |
| `ui_tap`, `ui_drag`, `ui_long_press` | Approximate touch classification, displacement, duration and tap count |
| `ui_touch_cancel` | A touch sequence was cancelled |
| `ui_control` | UIKit primary actions and value changes; switch/slider/segment state where available |
| `ui_scene` | Whether the reporting view's scene is active |

The observer uses a [public UIKit gesture recognizer](https://developer.apple.com/documentation/uikit/uigesturerecognizer) that never recognizes a gesture and cannot prevent the app's recognizers. It does not cancel or delay touches. It watches the active app window; it cannot observe other apps or system keyboard contents. UIKit controls are registered at startup and as their view ancestors receive touches. SwiftUI gestures are visible as physical input, but virtual SwiftUI, keyboard and VoiceOver actions are not all exposed as UIKit controls.

For exact semantic actions, add a breadcrumb in the action handler:

```swift
reporter.recordInteraction("open_settings", fields: ["source": "keyboard"])
```

Add stable `.accessibilityIdentifier("settings-button")` values to views wherever possible. Automatic interaction events record identifiers and view classes, not entered text or accessibility labels. App-supplied semantic fields go through the app's logger as provided.

`accessibility.json` is a bounded traversal of UIKit subviews and [public accessibility containers](https://developer.apple.com/documentation/uikit/uiaccessibilitycontainer), with parent IDs, classes, frames, identifiers, labels, hints and traits. It marks truncation after 500 nodes or depth 30. It omits accessibility values and skips text-field/text-view subtrees. Other visible labels and hints can contain app content, just as the screenshot can. This is not the private VoiceOver/XCTest AX tree; some virtual SwiftUI elements may be absent. The file describes its scope and redaction explicitly.

For a custom UIKit flow, `AccessibilitySnapshot.capture(view)` exposes the same JSON snapshot. The lower-level writer accepts `BugDiagnosticsSnapshot` to attach pre-captured data.
