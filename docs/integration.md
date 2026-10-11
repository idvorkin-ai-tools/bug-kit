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

For Apple dictation, add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` to Info.plist before setting `dictation = true`. A cloud provider that does not require Apple Speech needs only the microphone usage description.

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

### Reset What's new before UI tests

Create and retain `WhatsNewSeen(launchHookPrefix: "GRABBER", logger: logger)` in app initialization, before the home view first calls `showsRow`. Pass that same store to `WhatsNewRow`. CG tests can then launch with `GRABBER_WHATS_NEW_RESET=1` in `XCUIApplication.launchEnvironment` (or `SIMCTL_CHILD_GRABBER_WHATS_NEW_RESET=1` with simctl). Other apps substitute their prefix. Only the exact value `1` enables the hook.

The initializer synchronously clears `bugkit.whats_new_seen` and logs `bug_hook` with `whats_new_reset: true`. Custom defaults suites and keys are respected. Construct the store once per launch; recreating it during view rendering would reset a dismissal made during that launch. `reporter.runLaunchHooks()` handles report/shake hooks; it does not reset this store. Remove CG's manual plist deletion workaround after adopting this initializer.

### Let people remove screenshot attachments

Apps using `BugReportSheet` get the screenshot ✕ automatically after updating BugKit; no option is required. EA can remove its screenshot-drop workaround if present. CG must first adopt the shared sheet to receive this UI. Custom sheets call `reporter.dropScreenshot()`. Context and diagnostics remain attached. `.keepMoment` keeps the removal for subsequent notes; `.recapture` takes a new screenshot. The writer logs `screenshot_dropped: true` when explicitly removed; an ordinary capture failure does not set it.

### Delay automatic launch reports until the target screen is ready

`<PREFIX>_BUG_AFTER=<seconds>` controls when `<PREFIX>_BUG` captures and saves its reports. The default remains 2 seconds. Values must be between 0 and 86400 seconds (one day); invalid, negative, non-finite and larger values fall back to 2. Zero is allowed. Setting the delay alone does not create a report, and it does not change `_SHAKE_AFTER`, which accepts the same range and is ignored outside it. The `bug_hook` event includes `bug_after`.

For EA's cold-launch `bug_again` smoke check, set `SIMCTL_CHILD_SWING_BUG_AFTER=10` alongside `SIMCTL_CHILD_SWING_BUG="first of two|second of two"` when calling `simctl launch`. Tune the delay to that app's cold startup and assert that the clip/load event precedes each report. For XCUITest, set `SWING_BUG_AFTER` in `launchEnvironment`. This is a fixed delay, not a readiness signal, so a slow launch can still exceed it. Other apps substitute their own prefix.

## Voice input providers

Enable `options.dictation = true` for the microphone button and microphone menu. Apple Speech remains the default. Choose “Refresh microphones” to load the available ports and request mic permission if needed, then choose a mic before starting. The choice is retained in `bugkit.dictation_microphone`; before a fresh list is loaded, it is shown as “Saved microphone”. “Automatic” clears the preference and lets iOS route input. Opening a report never prompts for mic permission, queries inputs, or reconfigures audio.

Explicit Refresh temporarily activates a mixing audio session to discover inputs, then restores the app's category, mode, category options and preferred input. Before restoring a non-mixing category or options that duck or interrupt other audio, it releases the temporary session with `.notifyOthersOnDeactivation`; a busy deactivation error does not discard the listed inputs. Plain ambient or `.mixWithOthers` hosts keep their session active. Refresh can change audio routes or stop host playback, so apps should also return `true` from `microphoneBusy` during playback that must not be interrupted. After actual dictation capture, ambient sessions are deactivated as before.

Hosts with active recording should return `true` from `microphoneBusy`. BugKit checks it again after permission and provider startup, before touching the audio session, and skips discovery or capture if the host has become busy. Direct `NoteDictation` users can supply the same live check through its `hostMicrophoneBusy` initializer argument.

The input is a preference: iOS decides the actual route, and headset selection may also change playback routing. A selected mic that disappears is cleared from the picker on refresh. A route change or interruption during capture stops dictation and preserves the note; select the replacement and start again. Switching inputs during a dictation is intentionally disabled. Actual USB/Bluetooth hardware routing needs verification on a device.

For Deepgram, keep the vendor key in the app's key store, or have your server issue a short-lived access token:

```swift
var options = BugReporterOptions()
options.dictation = true
let hooks = BugReporterHooks(
  logger: log.logger,
  dictationProvider: {
    DeepgramDictationProvider(credential: {
      .accessToken(try await speechServer.fetchDeepgramToken())
      // Or: .apiKey(try await keyStore.deepgramKey())
    })
  })
let reporter = BugReporter(hooks: hooks, options: options)
```

`fetchDeepgramToken` and `keyStore` are your app's code; BugKit does not provide a token server or store keys. Deepgram receives audio when this provider is selected, so the app's voice-input/privacy text should describe that. No vendor credentials or spoken text are written into dictation event logs. The adapter uses [Deepgram's streaming Listen API](https://developers.deepgram.com/reference/speech-to-text/listen-streaming), with Nova-3 by default, configurable model/language, and [API-key or temporary-token authentication](https://developers.deepgram.com/guides/fundamentals/token-based-authentication). It sends `CloseStream` and drains final results before saving.

To use your own server/library, conform an actor or a Sendable type to `BugDictationProvider`, then return a fresh instance from the same hook. `start()` returns an `AsyncThrowingStream<String, Error>`. Each value is the complete spoken text so far, replacing the previous spoken value. BugKit prefixes the text typed before dictation. Audio chunks passed to `appendAudio` are mono signed little-endian PCM16 at 16 kHz. `finish()` must drain final text and close the stream; `cancel()` must promptly unblock stream and network work. The capture queue is bounded; a service that falls behind reports an error rather than dropping words silently.

“Log it” and “Log it and another” wait for the provider's final words. A finish failure keeps the sheet and current note open. Cancel/dismiss invalidates permission, audio and provider callbacks so they cannot write into a later report. The UI shows startup/finish progress and disables duplicate operations.

`voice-keyboard/ios/Host/AudioCapture.swift` and `DeepgramEngine.swift` were the design reference for input selection and streaming segment finalization. Its private `Engine` interface is different; an existing app-owned engine needs a `BugDictationProvider` adapter. Apps already using the shared BugKit report sheet get the mic menu when they enable dictation. CG/EA can opt into Deepgram by adding the factory hook; Mac apps can use the provider API with their own PCM capture, since the shared report sheet and mic picker are iOS views.

## App Group storage

For a host app that shares evidence with an extension, point the store and log at an explicit directory inside the App Group. Enable the same App Group entitlement on the host and whichever extension writes its own evidence. Resolve it through `FileManager`; do not hard-code the container's UUID or silently fall back to the app's private Documents.

```swift
guard let group = FileManager.default.containerURL(
  forSecurityApplicationGroupIdentifier: "group.com.example.voicekeyboard"
) else { fatalError("Missing App Group entitlement") }
let documents = group.appendingPathComponent("Documents", isDirectory: true)
try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
let store = BugStore(documents: documents)
let log = SessionLog(prefix: "host", documents: documents)
CrashReports.shared.install(folder: documents.appendingPathComponent("crashes"), logger: log.logger)
let reporter = BugReporter(
  hooks: BugReporterHooks(sessionLog: { log.position }, logger: log.logger, flushLog: { log.flush() }),
  store: store)
```

Keep report paths relative to this `documents` root. Add `"app_group": "group.com.example.voicekeyboard"` to this app's listener entry; it then pulls the group's `Documents` through `appGroupDataContainer`, including logs and crash evidence. Existing entries without `app_group` still pull the app container. [Listener configuration](ops/listener.md#configure) includes the full entry and backfill commands.

For memory-constrained keyboard extensions, link BugKit into the **host target only**, leave it out of the extension's package dependencies/link phase, and keep the extension's existing minimal evidence writer. The host can read or attach that evidence through its hooks. Do not assume the UIKit reporter is extension-safe: it uses `UIApplication`. Use distinct filenames or process prefixes for host and extension logs; this directory example does not establish cross-process safety for shared log/crash writers. A separate extension-safe product is tracked in [#26](https://github.com/idvorkin/bug-kit/issues/26).

## Private-text apps

An app displaying transcripts or other private text can disable automatic screen images while keeping the issue note and its app-supplied state:

```swift
var options = BugReporterOptions()
options.captureScreenshots = false
options.dictation = false
options.captureAccessibility = false
options.recordInteractions = false
let reporter = BugReporter(hooks: hooks, options: options, store: store)
```

`captureScreenshots` defaults to `true`. Turning it off skips the renderer for the sheet, “Log it and another” recapture, and launch-hook reports. No screenshot is displayed or written by those paths. Automatic reports already have no screenshot. The other three capture features default to `false`; set them explicitly here so this privacy configuration is easy to audit. These options do not redact the user's note, app-provided context, session logs or `extraFiles`: the app must keep dictated text out of those hooks and logs. Apps calling `BugReportWriter.save` directly own their `screenshotPNG` argument.
