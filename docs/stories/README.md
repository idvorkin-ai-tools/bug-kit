# BugKit user stories

These stories are BugKit's spec. Each one merges the stories that Exercise Analyzer (EA), Context Grabber's native app (CG) and Magic Monitor (MM) wrote for reporting problems, logs and What's new. "From" names the app story or issue it came from.

Each story uses the apps' format:
- **Summary**: one line.
- **From**: the source story or issue.
- **Status**: what in BugKit implements the story, and which test verifies it, by rung.
- **Use Case**: who wants it, what they want, and why.
- **Acceptance Criteria**: Given / When / Then scenarios.

There is no story without a test or a named rung. Where the only check is a device, the Status line says so.

The rungs are described in [../ops/test-ladder.md](../ops/test-ladder.md):
- **host** means `swift test` or the listener's pytest;
- **typecheck** means the iOS UI compiled against the iOS SDK;
- **device** is an app on a real phone or iPad.

| File | Stories |
|---|---|
| [01-reporting.md](01-reporting.md) | 001–009: the shake, the dialog, "Log it and another", dictation, the keyboard |
| [02-evidence.md](02-evidence.md) | 010–016: the report on disk, the session log, retention, extra files, crashes |
| [03-off-the-device.md](03-off-the-device.md) | 020–025: pulling, filing once, the listener, never uploading pictures |
| [04-whats-new.md](04-whats-new.md) | 030–033: What's new, built from git and the stories |

The persona is the same in all three apps: one person who uses the app every day on a phone, an iPad or a Mac, and the agents that fix what that person reports.
