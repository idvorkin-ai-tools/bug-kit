# The test ladder

Verify every change on the cheapest rung that can see it, and **name the rung** in the commit, the issue comment and the handoff, for example "verified on the simulator, not on the phone". An unnamed rung makes the next session verify it again.

| Rung | Cost | What it sees |
|---|---|---|
| Host | about 1 s | Pure logic in a Swift package: `swift test` |
| Mac lab | seconds | The real model or pipeline on recorded input on the Mac (EA `just analyze clip.mov`; MM `just selftest` on a clip) |
| Simulator | minutes | The app running: launch hooks, assertions on the session log |
| Device | a human | Camera, sensors, signing, real iCloud, the feel |

## Rules

- **Put logic in a Swift package** so the host rung can see it. BugKit itself does this: the report format, the store, the dialog's flow, the shake gesture, log retention and What's new are host-tested, and only the views are not.
- **Simulator checks assert on log events** (`jq` over the session log), not on screenshots or UI automation.
- **A wrong result from data gets a fixture first.** Turn the recorded input into a host test that fails, then fix the code. Never tune by reinstalling (EA).
- **Keep long test reports in a file.** SwiftPM caps a test's stdout and silently cuts long reports.
- **Close issues only after the verifying rung has run.** Use `Fixes #N` in the commit when that rung already ran; otherwise close by hand once the build is on the device. Either way, name the rung and the log line that proves the fix, for example `watch_inbox stuck 14 recovered 2` (EA #197), and say what the person should feel.
- **Swift Testing with only the Command Line Tools:** the macro plugin can fail about 2 builds in 3 with "plugin for module 'TestingMacros' not found". Pass `-Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib` (MM).

## The rungs in each app

| | Host | Mac lab | Simulator | Device |
|---|---|---|---|---|
| EA | `just test` | `just analyze` | `just test-sim`, plus `just watch-screens` | `just run-device`, then `just pull-logs` |
| CG native | `just native-test` | none | `just native-test-sim` | `just native-run-device`, then `just pull-logs` |
| MM | `just test` | `just selftest` | `just ipad-selftest` | `just ipad` |
| BugKit | `swift test`, plus the listener's pytest | none | none of its own; an app's simulator checks use the launch hooks | an app that has migrated |
