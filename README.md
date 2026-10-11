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

Create one reporter at launch and attach it to your root view. This minimal app uses BugKit’s session logger:

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
