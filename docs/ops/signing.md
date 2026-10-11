# Keeping automatic signing working

## The model

- **The projects use automatic signing.** XcodeGen `project.yml` sets `DEVELOPMENT_TEAM: <team-id>` and `CODE_SIGN_STYLE: Automatic`.
- **There is no API key, no fastlane and no hand-made profile.** The only credential is the Apple ID session that the Xcode app holds.
- **Profiles are cached** in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. The older `~/Library/MobileDevice/Provisioning Profiles/` is empty on current Xcode.

## Which builds need the account

**No account needed:**
- **Covered builds.** When the cached profiles already cover the device and every entitlement, `-allowProvisioningUpdates` changes nothing and the build signs offline.
- **New plain bundle ids.** The wildcard "iOS Team Provisioning Profile: *" covers a brand-new bundle id with no special capabilities.

**Account needed:** anything that changes the developer portal:
- a device that is not in the profile yet (the first build for a new iPad);
- a new capability or entitlement: iCloud, App Groups, HealthKit.

Without the account these fail with:

```
error: No Accounts: Add a new account in Accounts settings.
error: Provisioning profile "iOS Team Provisioning Profile: <bundle-id>" doesn't include the <X> capability.
error: Provisioning profile "…" doesn't support the iCloud.<bundle-id> iCloud Identifier.
error: Provisioning profile "…" doesn't support the group.<bundle-id> App Group
```

The apps hit each of these:
- EA, the iCloud container for sync (EA #209/#211), and HealthKit for the watch;
- CG, a new App Group;
- both, a new iPad.

## Checking whether the account is there

- **The only reliable check is one device build that needs the portal.** Grep its output for `No Accounts`.
- **Don't trust `defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists`.** In Xcode 27 it listed the account while builds failed with No Accounts, and it was empty while a build signed and registered a new device.
- **Don't search the keychain.** There is no item to find either way.
- **When reading Xcode's unified log,** use `/usr/bin/log`, because in zsh `log` is a builtin. Read it within the hour. Filter out token, session, password and authorization lines before writing anything down: one search once captured a live session token. The header names to drop are `X-Apple-GS-Token` and `DSESSIONID` (CG), as in `/usr/bin/log show … | grep -v -i -E 'X-Apple-GS-Token|DSESSIONID|token|password|authorization'`.

## Fixing it

1. Have the person sign in at **Xcode › Settings › Accounts**. There is no command-line sign-in.
2. Straight away, run the build that needs the portal, **first and alone**, under the lock. It registers the device or adds the capability, and Xcode caches the new profile.
3. From then on, builds that need no new portal change keep working even if the account drops again. The iCloud capability is the usual case: one signing build after sign-in, then cached-profile builds work.

The account dropped about 30 minutes after each sign-in on 2026-10-07. The cause is unproven. One suspect is that a background launchd session (an agent's shell) cannot refresh the token.

## Don'ts

- **Don't strip entitlements from `project.yml` to get a build through.** The app then ships without the capability: a widget showed only its placeholder. A new device still fails, because it is in no cached profile (CG, 2026-10-06/07).
- **Don't clear the cached profiles while the account is unreliable.** Builds that work would start failing.
- **Don't run two signing builds at once** (see [deploying.md](deploying.md)).

## A new device

1. Find it in `xcrun devicectl list devices`. Keep its id out of the repo: use a gitignored file or none at all, because the scripts here find devices by model.
2. With the account signed in and no other signing build running, build once with that device as the destination and `-allowProvisioningDeviceRegistration`: `scripts/deploy-all.sh <app> --register <device>`.
3. From then on, normal builds and installs cover it.

## Simulator builds

Simulator builds need no team:
- EA uses `CODE_SIGNING_ALLOWED=NO`.
- CG uses `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual`, "signed to run locally, not unsigned": HealthKit refuses an app without its entitlement, even on the simulator.
- A Mac app built ad hoc (`codesign --force --sign -`) loses its Accessibility grant at every rebuild.

## Mac apps signed ad hoc

- **Every rebuild changes an ad-hoc signature, and macOS may ask for camera, microphone or screen-recording access again.** TCC ties the grant to the signature. When relaunching a rebuilt Mac app, tell the person a permission prompt may be waiting. Otherwise the app looks frozen on a blank camera (MM AGENTS.md).
