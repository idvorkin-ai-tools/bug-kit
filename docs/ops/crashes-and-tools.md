# Crashes, hangs and other device tools

## Reading a crash

- **The session log tells you what was running.** A `crash_report` line at the next launch names a file under `crashes/`.
- **A MetricKit payload `<stamp>.json`** has the exception type, the signal, the termination reason and the stack trees as addresses.
- **The app's own files:** `signal-<epoch>.txt` holds the crashing thread's raw backtrace, and `exception-<epoch>.txt` holds the Objective-C exception's name, reason and symbolized stack. MetricKit can take days on a development build, so these are often first.
- **A log that just stops, with no crash file, means a kill from outside the process,** most often the memory limit (SIGKILL cannot be caught). Read the memory footprint in the periodic status lines, and confirm with Instruments' Allocations.
- **A log that stops with the app in the background,** with no crash file, is iOS suspending it. This is why the scene phase is logged.

## Hangs: 0x8BADF00D

- **The watchdog kills an app whose main thread is stuck for about 10 s,** with the termination code 0x8BADF00D (scene-update). MetricKit reports the hang, and BugKit logs it as `crash_report` kind hang.
- **EA's iPad was killed this way by its iCloud sync** (EA #231). At every `NSMetadataQuery` update it asked for downloads one file at a time on the main thread: thousands of synchronous FileProvider calls. The fix moved the requests off the main thread and asked once per file.
- **EA was killed this way once before,** when a camera session released on the main thread waited on its busy capture queue (EA #86).
- **What to do:**
  - Read the main thread's stack in the hang payload first.
  - Keep FileProvider, `NSFileCoordinator` and AVFoundation teardown off the main thread.
  - Log how long each such pass takes.

## Symbolicating a MetricKit payload

Use the dSYM from the same build as the crash, which is normally the last device build:

```sh
DSYM=$(find Build/Build/Products/Debug-iphoneos -maxdepth 1 -name "App.app.dSYM" | head -1)
BIN="$DSYM/Contents/Resources/DWARF/App"
jq -r '.crashDiagnostics[]? | (.callStackTree.callStacks[] | select(.threadAttributed == true) | .. | objects
  | select(has("address")) | "\(.binaryName // "?") \(.offsetIntoBinaryTextSegment // 0)")' crash.json |
while read -r name off; do
  if [ "$name" = App ]; then atos -o "$BIN" -arch arm64 -l 0x0 "$(printf '0x%x' "$off")"; else echo "$name +$off"; fi
done
```

EA and CG each ship this as `scripts/symbolicate.sh` (`just symbolicate <file>`).

## The device's own crash reports

- **libimobiledevice** (USB, after `idevicepair pair`): `idevicecrashreport -k <dir>`, then look for the app's name.
- **CoreDevice:** `xcrun devicectl device copy from --device <id> --domain-type systemCrashLogs --source / --destination <dir>`.

## Instruments from the command line

```sh
xcrun xctrace record --template "Allocations" --device <udid> --attach <ProcessName> \
  --time-limit 90s --output ~/tmp/agent/traces/$(date +%Y%m%d-%H%M%S)-alloc.trace
xcrun xctrace export --input <trace> --toc            # list its tables; --xpath to export one
```

- Templates the apps used: Allocations, Leaks, Time Profiler, Core ML, Activity Monitor.
- Launch the app first, and do the action inside the recording window.

## Getting media off the device

- AirDrop it to the Mac.
- If the clip is in iCloud Photos, export the original with Photos' scripting.
- Traps:
  - a Live Photo's `.mov` shares the still's name and is a 3 s clip;
  - an original that iCloud has not downloaded exports slowly or not at all;
  - the phone's Photos library cannot be read from the Mac.
