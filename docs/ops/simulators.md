# Simulator lessons

## One named simulator, headless, one at a time

- **Give each repo or task its own simulator, booted headless, and never use `open -a Simulator`.** Delete throwaway simulators when done.

  ```sh
  xcrun simctl create <repo>-ipad <device-type>
  xcrun simctl bootstatus <udid> -b
  ```

- **One simulator on the Mac at a time** (see [runners.md](runners.md)).
- **Resolve names to UDIDs.** Every Xcode update leaves a second "iPhone 17" behind on the older runtime, so a boot by name and a launch by name can land on different devices (EA and CG `sim-udid.sh`):

  ```sh
  xcrun simctl list devices available | grep -F -- "    $name (" | tail -1 | grep -oE '[0-9A-F-]{36}'
  ```

  `tail -1` picks the newest runtime, which is listed last.
- **Boot explicitly before `xcodebuild test`** when other simulators are up. Otherwise the test dies with "Timed out trying to boot simulator after 60 s".
- **Rerun before believing a first-run failure.** The first run on a just-made simulator can stall about 11 s before its first frame (MM).

## Driving the app without tapping

- **Launch hooks.** Use `SIMCTL_CHILD_<APP>_<ACTION>=… xcrun simctl launch <udid> <bundle>`. simctl strips the prefix, so the app reads `<APP>_<ACTION>`.
  - BugKit's `launchHookPrefix` gives `<APP>_BUG` and `<APP>_SHAKE_AFTER`.
  - EA has about 30 `SWING_*` hooks.
- **Wait for an event in the new launch's log, not a fixed time.** Remember the newest log before the launch and require a different file. Treat a timeout as a failure even if old data would match.
- **Privacy prompts:** `xcrun simctl privacy <udid> grant photos|microphone|location|location-always <bundle>`.
  - There is no camera service, and the simulator has no camera.
  - HealthKit's sheet cannot be granted from simctl. CG taps it once per simulator from a UI test.
- **Deep links:** open them from an XCUITest (`XCUIApplication().open(url)`). `simctl openurl` stops at an "Open in…?" prompt no script can answer.
- **Services the simulator lacks:** use one environment variable to point the app at a plain stand-in. EA's `SWING_SYNC_DIR` stands in for the iCloud container, and two simulators sharing it test sync end to end.

## A smoke script on `scripts/smoke-lib.sh`

Each app keeps its own checks. The plumbing is shared: source `scripts/smoke-lib.sh` from the BugKit checkout.

| Helper | What it does | From |
|---|---|---|
| `launch APP_BUG=x …` | terminates, remembers the newest log, launches with `SIMCTL_CHILD_` hooks | EA, CG |
| `wait_for <type> <secs>` | waits for an event in a log newer than the launch; a timeout fails the run | EA `sim-smoke.sh` |
| `require_event <type> [jq] [label]` | this launch's log has the event; `require_event selftest_finished` is the finish marker | MM's selftest |
| `fail_on_errors [label]` | any `error` event in this launch's log fails the run, naming `where` and `message` | CG `sim-smoke.sh` |
| `stash <paths>` / `unstash` | moves Documents paths aside and back, also on exit or Ctrl-C; a stash a killed run left is put back first | EA |
| `run <check> …` | runs the check unless `ONLY=<substring>` excludes it | EA |
| `smoke_done` | prints the result and exits 1 on any failure | |

- **A scripted flow logs that it finished** (`selftest_finished`, or the app's own name for it) as its last line. A
  crash or an early quit then fails the run instead of passing with whatever was logged before it (MM).
- **Any `error` event fails the run**, even when the feature under test passed. BugKit logs every failed step as
  `error`, and this gate turns those into failures (CG).

## Preferences: plist edits need cfprefsd restarted

- **For a key the app has never written,** use `xcrun simctl spawn <udid> defaults write <bundle> <key> <value>`. The app reads it.
- **For a key the app has already written,** that write is silently ignored, because the app's container plist wins.
- **Editing that plist alone is not enough either.** The simulator's cfprefsd keeps the domain cached after the app quits, so it does not read the edit, and the app's next save writes the cached keys back over it (EA PR #216).

What works:

```sh
prefs="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Library/Preferences/$BUNDLE.plist"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
[ -f "$prefs" ] || { mkdir -p "$(dirname "$prefs")"; plutil -create xml1 "$prefs"; }
plutil -replace <key> -bool true "$prefs"              # -date, -string, … per type
xcrun simctl spawn "$SIM" launchctl kill SIGTERM system/com.apple.cfprefsd.xpc.daemon || true
sleep 1
xcrun simctl launch "$SIM" "$BUNDLE"
# afterwards: plutil -remove <key> "$prefs", and the same cfprefsd restart
```

A check deletes what it set. One hook's mode leaked into later launches until it did (EA #57).

## First-run state: erase needs shutdown

- **Reset a simulator to first-run state** with `xcrun simctl shutdown <udid> && xcrun simctl erase <udid>`. Erase refuses a booted simulator.
- **`simctl uninstall` fails on a shut-down simulator and leaves the old settings behind.** A test once failed because a previous run's "seen" setting survived a silently failed uninstall (CG).

## Other mechanics

- **Waiting for the app to exit:** capture `jobs=$(xcrun simctl spawn "$sim" launchctl list)` first, then grep the variable. Piping straight into `grep -q` under `pipefail` ends the wait early, which once looked like a crash (MM).
- **Screenshots:** `xcrun simctl io <udid> screenshot out.png`. Delete the old file first, so a previous run's picture cannot pass for this one.
- **App container:** `xcrun simctl get_app_container <udid> <bundle> data`.
- **App log:** `xcrun simctl spawn <udid> log show --predicate 'subsystem == "<subsystem>"' --info`.
- **Order-sensitive UI tests:** a test that hands off to Safari can break the next test in the same run. Run it alone.
- **Speed:** the simulator runs Core ML on the CPU, about a tenth of the phone's speed. Wait on events, not on time.
- **Fresh worktrees:** a fresh worktree lacks gitignored model files, so the app launches with no model and every check times out.
- **Watch simulators:** WatchConnectivity's `transferUserInfo` does not cross between paired simulators. To stage a lost phone, shut the phone simulator down; terminating the app is not enough, because watch messages relaunch it.
