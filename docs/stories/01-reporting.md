# Reporting a problem

Part of the [BugKit stories](README.md).

---

### User Story 001:

- **Summary:** Report a problem in five seconds with the evidence attached
- **From:** EA story 022; CG story 142; MM story 040
- **Status:** `BugReporter`, `BugReportSheet` and `BugReportWriter`.
  - The writer is verified on the host by `writerSavesTheScreenshotTheExtraFilesTheLineAndTellsTheLogger`.
  - The sheet is verified by typecheck.
  - The dialog on a device waits for the first app to migrate.

#### Use Case:
- **As someone** who just saw the app do something wrong
- **I want to** shake the device, type one line and move on
- **so that** the developer gets the screen, the build and the session log without my explaining

#### Acceptance Criteria:
- **Scenario:** A shake
- **Given:** the app is open on any screen
- **When:** I shake the device, type "counted 1 rep, there were 13" and tap *Log it*
- **Then:**
  - the report is stored as one line in `Documents/bugs.jsonl`, with my note, a picture of the screen as it was at the shake, the screen's name, the build and commit, and the session log's path with the moment in it;
  - the session log has `bug_report_open` and `bug_report`;
  - the app can show "Problem logged. Thanks."

- **Scenario:** Changing my mind
- **Given:** the dialog is open with a note typed
- **When:** I tap *Cancel*, press Escape, or swipe the sheet down
- **Then:** nothing is saved, the log has `bug_report_cancel`, and nothing else in the app changed

---

### User Story 002:

- **Summary:** The report opens over whatever is on screen, sheets included
- **From:** EA #41; CG #182 (story 142, "A shake over a dialog")
- **Status:**
  - `BugReporter.open` captures the key window, then presents from `BugReporter.topmost`. Verified by typecheck.
  - CG's `ShakeOverSheetUITests` covers the same design in CG.
  - BugKit's own presentation over a sheet is a device check, still to do.

#### Use Case:
- **As someone** reporting a problem with a settings sheet or a list open
- **I want to** have the report open on top of it and the sheet still there afterwards
- **so that** reporting never loses my place, and the picture shows what I was looking at

#### Acceptance Criteria:
- **Scenario:** A shake over a sheet
- **Given:** a sheet is up (settings, a list, a naming card)
- **When:** I shake, then cancel; and shake again
- **Then:**
  - the report opens over the sheet each time, and its picture shows the sheet;
  - after *Cancel* or *Log it* the sheet is still there;
  - `bug_report_open` says what it opened `over`.

- **Scenario:** A second shake while typing
- **Given:** the dialog is open with half a note typed
- **When:** the device is shaken again
- **Then:** the note is kept, and the log says `already_open` (`aSecondShakeWhileTypingKeepsTheNote`, host)

---

### User Story 003:

- **Summary:** Several problems in a row: "Log it and another"
- **From:** EA #212 (story 022); MM story 061 (mmn-2jn); CG story 142, a85e228
- **Status:**
  - `BugReportFlow.log(another:style:)`, verified on the host by `logItAndAnotherSavesThenOpensAFreshReport` and `recaptureClosesThenReopensAFreshReport`.
  - Unique folders within one second are verified by `folderNamesAreUniqueWithinOneSecond`.
  - Two saves at once are verified by `sixtyFourConcurrentAppendsGiveSixtyFourValidLines`.

#### Use Case:
- **As someone** who noticed several things wrong at once
- **I want to** save a report and be straight back in an empty one
- **so that** I file each bug on its own, without shaking again for each

#### Acceptance Criteria:
- **Scenario:** Keep the moment (`another: .keepMoment`, the default)
- **Given:** a report has a note typed
- **When:** I tap *Log it and another*, type a second note and tap *Log it*
- **Then:**
  - two reports are stored, each with its own note, both with the shake's picture;
  - the dialog stayed up between them, and its note field was empty and focused.

- **Scenario:** A fresh picture each time (`another: .recapture`)
- **Given:** the app chose `.recapture`
- **When:** I tap *Log it and another*
- **Then:**
  - the dialog closes;
  - once it is off screen, the screen underneath is captured again;
  - a fresh, empty dialog opens with `source` "another".

- **Scenario:** Two in one second
- **Given:** two reports are saved within the same second
- **Then:**
  - they get folders `<stamp>` and `<stamp>-2`;
  - `bugs.jsonl` has both lines, neither overwriting the other (MM mmn-cfr).

---

### User Story 004:

- **Summary:** A gentle shake opens the report, not only a hard one
- **From:** CG story 146 (#164)
- **Status:**
  - `ShakeGesture` (host: `aQuickLightShakeIsAShake`, `onePushIsNotAShake`, `aSlowSwayAndAWeakJiggleAreNotShakes`, `oneShakeOpensOneSheet`).
  - `ShakeMotion`, behind `options.gentleShake` (on by default), verified by typecheck.
  - The threshold on a device was not checked in BugKit. CG has not checked it on a phone either.

#### Use Case:
- **As** the person reporting problems many times a day
- **I want to** open the report with a quick, gentle shake
- **so that** reporting stays a reflex, not a workout

#### Acceptance Criteria:
- **Scenario:** A quick back-and-forth
- **Given:** the app is open and in front
- **When:** I give the device three quick, light flicks (about 1.8 g) that iOS's own shake ignores
- **Then:**
  - the report opens once;
  - the log has `shake` with source motion and `peak_g`;
  - walking with the device, or setting it down on a bench, opens nothing.

---

### User Story 005:

- **Summary:** A button, and ⌘I on a keyboard, for when shaking is awkward
- **From:** MM story 040 (⌘I), MM story 09 (iPad: Settings → Report a bug); EA's "Report a problem" on the start panel; CG Diagnostics
- **Status:**
  - `BugReportButton` and `options.commandI`, verified by typecheck.
  - `shakeEnabled = false` silences shakes during instrumented runs (EA story 037).

#### Use Case:
- **As someone** with the iPad on a stand, or typing on a keyboard
- **I want to** open the report with a button or ⌘I
- **so that** I can report without picking the device up

#### Acceptance Criteria:
- **Scenario:** ⌘I on the iPad
- **Given:** a hardware keyboard is attached
- **When:** I press ⌘I
- **Then:** the report opens as a shake would, and `bug_report_open` has source `key`

---

### User Story 006:

- **Summary:** Keys inside the dialog
- **From:** MM story 040 ("press Return"), story 061 (⌘Return for Save and Another)
- **Status:** `options.dialogKeys`, verified by typecheck.
  - In BugKit, ⌘Return is *Log it* and ⇧⌘Return is *Log it and another*.
  - This differs from MM, where Return saves and ⌘Return saves another. BugKit's note field is multi-line, so Return types a new line.

#### Use Case:
- **As someone** reporting from a keyboard
- **I want to** save, save-and-another and cancel without the mouse or a tap
- **so that** reporting does not interrupt my hands

#### Acceptance Criteria:
- **Scenario:** Keyboard only
- **Given:** the dialog is open with a note
- **When:** I press ⌘Return / ⇧⌘Return / Escape
- **Then:** the report is logged / logged with a fresh one opened / cancelled

---

### User Story 007:

- **Summary:** Speak the note
- **From:** CG #239 (story 142, "Speaking the note")
- **Issues:** #7, #1 (voice-input clarification); beads bug-9j5, bug-ig8
- **Status:**
  - `NoteDictation`, behind `options.dictation` (off by default: it needs the speech and microphone usage strings). Verified by typecheck.
  - `DictationText.merge` is verified on the host by `dictatedWordsGoAfterTheTypedNote`.
  - The permission prompts and music carrying on are device checks, still to do.
  - The error is a `BugProblemView` with Copy error, behind `options.copyableErrors` (on), from CG's ProblemView
    (bug-kit#7). The copied text is verified on the host by `BugProblemTests`; the view by typecheck. Pasting from a
    real refusal is a device check, still to do.

#### Use Case:
- **As someone** with one hand on a kettlebell or a steering wheel
- **I want to** tap the microphone and say what went wrong
- **so that** a report takes no typing

#### Acceptance Criteria:
- **Scenario:** Speaking
- **Given:** the dialog is open, with or without words typed, and no call is up
- **When:** I tap the microphone, say "the timer skipped the rest", and tap it again
- **Then:**
  - the words appear after anything I had typed;
  - music that was playing keeps playing;
  - the log has `dictation_start` and `dictation_stop`.

- **Scenario:** The microphone is busy or refused
- **Given:** a call holds the microphone (`microphoneBusy`), or speech recognition is off
- **Then:**
  - the button is off, or the dialog says why in words;
  - the log has `dictation_error` with the reason.

- **Scenario:** Copying the error
- **Given:** the dialog says why dictation failed
- **When:** I tap Copy error and paste into an issue
- **Then:**
  - the paste has the message, `context: BugReportSheet.dictation`, `build:` with the version and commit, and the
    state (`auth`, `mic`, `recognizer` or `error`, and `mic_busy`), one per line;
  - the log has `ui` with `action: copy_error` and `from: tap`.

---

### User Story 008:

- **Summary:** The dialog says where the report goes
- **From:** MM story 062 ("Nothing leaves this iPad"), story 040 ("nothing leaves the Mac")
- **Status:** `options.privacyNote`, shown under "Attached automatically". Verified by typecheck.

#### Use Case:
- **As someone** whose screen may show health data, places or a journal
- **I want to** see that the report stays on the device until the developer pulls it
- **so that** I report freely

#### Acceptance Criteria:
- **Scenario:** The note
- **Given:** the app set `privacyNote: "Nothing leaves this iPad."`
- **When:** the dialog opens
- **Then:** the line shows under what is attached

---

### User Story 009:

- **Summary:** A simulator can make reports without a hand (technical)
- **From:** EA `SWING_BUG` (story 026), CG `GRABBER_BUG` and `GRABBER_SHAKE_AFTER` (story 142)
- **Status:**
  - `BugLaunchHooks` is verified on the host by `launchHooksParseNotesAndShakeAfter`.
  - `BugReporter.runLaunchHooks` is verified by typecheck.
  - `scripts/smoke-lib.sh`, the shared plumbing for an app's smoke script (EA, CG and MM's rules), is verified on the
    host by `scripts/tests/test_smoke_lib.py` with a stub simctl. A real app's smoke script on it is still to come.

#### Use Case:
- **As an** agent verifying a change on the simulator
- **I want to** have the app save a report, or open the dialog, from an environment variable
- **so that** the check asserts on the log and the files instead of tapping

#### Acceptance Criteria:
- **Scenario:** Two reports from the hook
- **Given:** `launchHookPrefix: "APP"`
- **When:** the app launches with `SIMCTL_CHILD_APP_BUG="first|second"`
- **Then:**
  - two reports are saved about two seconds after launch, each with the screenshot;
  - the log has `bug_hook` and two `bug_report` lines.

- **Scenario:** A smoke check that cannot pass by accident
- **Given:** a smoke script on `scripts/smoke-lib.sh`
- **When:** the app crashes before it logs, the launch writes no new log, a step logs `error`, or the scripted flow
  stops before `selftest_finished`
- **Then:** the run fails and names why. An older launch's log never satisfies the check.

### Remove a screenshot before saving

**Issues:** #14

The screenshot thumbnail has an accessible “Remove screenshot” button. Removing it keeps the note and context but saves no screenshot path or `screen.png`, and the `bug_report` event includes `screenshot_dropped: true`. “Log it and another” retains this choice for `.keepMoment`; `.recapture` and a new presentation capture fresh evidence. Host coverage: `screenshotDropPersistsForSameMomentAndResetsOnRecapture`, `droppedScreenshotIsAbsentFromSavedReportAndFolder`.

### Delay automatic launch reports for cold startup

**Issues:** #19

Given `<PREFIX>_BUG` notes and `<PREFIX>_BUG_AFTER=10`, reports capture evidence after ten seconds instead of the default two. Invalid, negative, non-finite and over-one-day values retain the default; zero is accepted. A delay without notes does not save reports. Host coverage: `automaticReportDelayDefaultsToTwoSeconds`, `automaticReportDelayAcceptsOnlyFiniteNonnegativeValues`, `shakeDelayAcceptsOnlyBoundedNonnegativeValues`. EA's cold-launch smoke check can set `SWING_BUG_AFTER` and verify that the clip's load event precedes the report.

### Choose the microphone and transcription service

**Issues:** #1; beads bug-9j5, bug-ig8

With dictation enabled, the report offers Automatic and an explicit “Refresh microphones” action to load iOS inputs. Opening a report does not reconfigure audio. The saved input preference applies to a fresh dictation and shows as “Saved microphone” until refreshed. Missing inputs are cleared on refresh; changes during capture stop dictation without erasing text. Apple Speech is the default, while a host factory can choose Deepgram or another streaming provider. Cloud providers skip Apple Speech authorization. Typed words and finalized speech survive interim revisions; save waits for final words, and canceled permission/network callbacks cannot alter another report.

Host coverage (Foundation, `swift test`): `DictationProviderTests.swift` verifies transport, Deepgram handshake credentials, segment revisions, final flushing and cancellation. iOS simulator coverage (`Tests/iOS` bundle): `NoteDictationTests.swift` uses fake iOS capture/permissions to verify selected input, a saved microphone shown before any explicit refresh, no microphone discovery or capture while the host records (including when it starts recording during permission or provider startup), Apple's quiet end after Stop, final text before save, permission cancellation, service failure and disappeared-input fallback. Physical mic routes and live vendor transcription need separate device/service verification.
