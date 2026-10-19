# The app checklist

Every app that adopts BugKit follows this list. Each item links to the doc or API that implements it, so the list
stays short and the detail lives in one place. Link this page from each app's AGENTS.md.

## In the app

| Item | Done when | How |
|---|---|---|
| Report a problem | iOS: a shake (also over sheets and alerts), ⌘I on a hardware keyboard and a 🐞 button each open the report dialog. macOS: the app's own report action saves through `BugReportWriter` | iOS: [Quick start](../README.md#quick-start), `.bugReporting(reporter)` on the root view and `BugReportButton` in a toolbar. macOS: [macOS storage](integration.md#macos-storage-and-command-line-tools) |
| Rich diagnostics | Reports carry interaction breadcrumbs and the accessibility snapshot, and the main controls have stable `.accessibilityIdentifier`s | [UI diagnostics](integration.md#interaction-and-accessibility-diagnostics) |
| Private text | An app showing transcripts or other private text turns off screenshots, rich diagnostics and dictation | [Private-text apps](integration.md#private-text-apps) |
| Session log | One `SessionLog` per launch; the report names its position; old logs pruned at launch | [Integration](integration.md), [logging conventions](ops/logging.md) |
| Crash capture | `CrashReports.shared.install` at launch, after the session log | [Crash capture and automatic filing](../README.md#crash-capture-and-automatic-filing) |
| What's new | The `whats-new.sh` build phase, with each entry linked to its user story; the home screen shows `WhatsNewRow` | [Integration](integration.md), step 4; [user stories](stories/README.md) |
| About and version | A Settings row opens `BugKitAboutLink`: version, build and the commit linked to GitHub | [About / version in Settings](integration.md#about--version-in-settings) |
| CloudKit delivery | Opt-in, the shared container entitled, `prepare(documents:)` before showing the reporter, `start()` at launch and foreground | [Private CloudKit delivery](integration.md#private-cloudkit-delivery) |
| Watch | A watch app saves reports with `WatchBugReportView` and has its own `apps.json` entry | [watchOS reporting](integration.md#watchos-reporting) |
| BugKit pin | An exact BugKit tag, never `main`, bumped once per train | [Each app's agent](integration.md#each-apps-agent); trains are in mac-driver's `docs/rollout-trains.md` |

## Around the app

| Item | Done when | How |
|---|---|---|
| Listener entry | The app's bundle (and watch bundle) is in `~/.config/bug-kit/apps.json`, and `bug-listener doctor --json` is clean | [Setup checks](../README.md#setup-checks-and-agent-readable-status), [listener](ops/listener.md) |
| Signing | Automatic signing works for each device build | [Signing](ops/signing.md) |
| Deploying | One build per train, installed with `scripts/deploy-all.sh` under the signing lock | [Deploying](ops/deploying.md) |
| Simulators | One named simulator at a time, claimed with `scripts/with-simulator.sh` under `build.lock` | [Simulators](ops/simulators.md) |
| Test ladder | Each fix names the cheapest rung that proves it: host, simulator or device | [Test ladder](ops/test-ladder.md) |
| Shared bugs | A bug or practice that applies to every app is filed and fixed here, and the app's issue links to it | [Where a bug gets fixed](../README.md#where-a-bug-gets-fixed) |
