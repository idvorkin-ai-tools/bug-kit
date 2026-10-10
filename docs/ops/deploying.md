# Building and deploying to the phone, the iPad and the watch

## The device build

Every app's device recipe has this shape: EA `build-device` and `run-device`, CG `native-build-device`, MM `just ipad`.

```sh
xcodegen generate                      # if the project is generated: after any project.yml change, or the build uses the old one
xcodebuild -project App.xcodeproj -scheme App -derivedDataPath Build \
  -destination "platform=iOS,id=<udid>" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <id> Build/Build/Products/Debug-iphoneos/App.app
xcrun devicectl device process launch --device <id> <bundle-id>
```

- **`-allowProvisioningUpdates` lets Xcode create and refresh profiles. `-allowProvisioningDeviceRegistration` lets it add a new device to the team.** Every device recipe passes both.
- **Never pass `-sdk`.** It breaks the watch target (EA).
- **Run device builds with the sandbox off.** Provisioning needs it.
- **Quote product paths.** Some contain spaces (`Magic Monitor.app`).
- **Bake the commit into the app** with build settings (`GIT_SHA=$(git rev-parse --short HEAD)`), so reports and About say which build is running.

## A failed build must not install the old one

```bash
set -uo pipefail
out=$(xcodebuild … build 2>&1)
echo "$out" | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
echo "$out" | grep -q "BUILD SUCCEEDED"     # this line's status is the recipe's
```

- **`xcodebuild … | grep BUILD` alone exits 0 on "BUILD FAILED".** The next step then installed the previous bundle (EA #43). The same holds for `swift test | tail`: use `pipefail` (EA #51).
- **A failed install must not go on to launch the copy already on the device** (MM).

## One signing build at a time

Never run two `-allowProvisioningUpdates` builds at the same time on one Mac, across all agents.

- **The incident:** on 2026-10-07 one agent's signing build ran while another started. The second build failed with `No Accounts`, and a minute later Xcode's account list in its preferences was found empty. That is unproven as the cause, but it is the one correlation in the evidence.
- **The lock:** wrap the whole run, from project generation to launch, in a kernel lock:

  ```sh
  mkdir -p ~/tmp/agent/locks
  lockf -k -t 900 ~/tmp/agent/locks/xcode-signing.lock <the build and install>
  ```

  - `lockf(1)` holds the lock for the life of the command, so no lock goes stale.
  - `-k` keeps the file, so a waiter never locks one that was just removed.
  - `-t 900` gives up after 15 minutes.
  - MM adopted this after a process check alone let two runs in together (mmn-af8). EA and CG still need to adopt it; `deploy-all.sh` does it for them.
- **Inside the lock, also wait for signing builds that did not take it,** using an anchored pattern:

  ```sh
  pgrep -fl '^[^ ]*xcodebuild .*-allowProvisioningUpdates'
  ```

  A bare `pgrep -f xcodebuild` also matches other agents' shells that merely mention the word. It once counted 30 "builds" and held a build for 20 minutes. To ask whether any xcodebuild is running at all, use `pgrep -x xcodebuild`.
- **Don't run a simulator test while a signing build runs** (EA). Its waits fail under contention, and a check can read the previous result.

## Build once, install everywhere

`scripts/deploy-all.sh <app>` does this:

1. It takes the lock.
2. It waits for any unlocked signing build.
3. It builds once, for the first device.
4. It installs and launches on each paired iPhone and iPad.

It needs a `build` object in the app's entry in `~/.config/bug-kit/apps.json` (see `listener/apps.example.json`).

What happens on each device:
- **Locked device:** a launch refused while the device is locked (CoreDeviceError 10002, "could not be, unlocked") is a soft success. The app is installed and opens when unlocked. Report it that way and don't rebuild.
- **New device:** a device not yet in the provisioning profile fails to install a build made for another device. Run one build with that device as the destination, with the Xcode account signed in: `deploy-all.sh <app> --register <device>`. After that the cached profile lists it. CG registered an iPad this way on 2026-10-07. See [signing.md](signing.md).
- **The watch:** the watch app is embedded in the phone build (`App.app/Watch/AppWatch.app`), so `--watch` installs it from the same product. The watch takes an install only when it is on the wrist and awake. Errors 1011 or 4000, a "usage assertion" failure, or a timeout mean it is asleep, not that the build is bad. Say so instead of retrying.
- **Unverified:** that one `Debug-iphoneos` product installs on every device already in the profile. It follows from how automatic signing embeds the team profile, but no repo had done it in a script before `deploy-all.sh`, and `deploy-all.sh` has only been dry-run.

## Destination errors

- **"destination not found"** means the device is not on the network or not paired. Unlock it and retry; it is not a signing problem.
- **`devicectl` needs no Apple account.** Installing and launching keep working when signing does not.
