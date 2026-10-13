# Vision

`bug-kit` exists so that a problem seen on a device the agent cannot see reaches whoever fixes it with the evidence that settles it.
It serves Igor's own Apple apps, Exercise Analyzer, Context Grabber and Magic Monitor, and the agents that fix them.
It turns a shake, a crash or an app's own alarm into a report carrying its screenshot, log moment, build and context, and files it exactly once.
It owns exactly one thing: the one shared copy of the practices every one of Igor's apps needs to explain itself, starting with the path of a bug report from the device to the tracker.

## One copy, fixed here

A practice every app needs, like reporting a problem or What's new, belongs here rather than in three drifting copies.
A shared usage log belongs here too: which screens and features each app used, pulled to the owner's Mac as a summary.
A bug in the dialog, shake, dictation, store, crash capture, pruning, What's new, listener or scripts is fixed in BugKit, not in an app.
A fix lands here with a host test that fails before it and ships in a tagged release; each app pins a release and upgrades deliberately, and BugKit does not push version bumps into the apps.
An app works around a BugKit bug only through hooks or options, with a `ponytail:` comment naming the issue, never by copying code in.
A bug in an app's own hooks, its context, screen names, extra files or logger bridge, stays in that app.
A feature arrives because an app needed it, behind an option, with the existing behaviour as the default unless this vision sets the default, as it does for rich diagnostics.

## Evidence, not guesses

A device-only symptom gets a log event, a deploy and a pull before it gets a fix; a second guessed fix does not ship.
Every report names its session log and the millisecond moment in it, the screen, the build and the commit.
The screenshot is taken before the dialog appears, and a second shake never wipes a half-typed note.
Rich diagnostics, interaction breadcrumbs and the accessibility snapshot, are on by default in every app that adopts BugKit, and one option turns them off.
Silent passes and success paths log too, because no line cannot be told apart from never ran.
A step that fails is logged as its own error and the report is still saved.
A cause is stated only as far as the logs show it, and an inferred link, like a crash's session, is labelled inferred.
A fix is verified by a log line on a named rung, host, simulator or device, not by asking the user.

## Reports leave the device safely

By default, reports stay in the app's Documents until the owner's Mac pulls them with `devicectl`, and the device holds no token.
Filing straight from the device is an option an app can turn on, never the default, because a report can carry private information.
Before a report is saved, its author sees a preview of every attachment and can remove any of them with the X in its corner.
Screenshots reach the owner's Mac for triage, and go into a tracker only after a person scrubs private information from them, for example by drawing over it; an automatic scrubber never makes that call alone.
Text entry and accessibility values never enter the diagnostics.
Automatic reports are rate-limited per reason and capped in size, and they may capture the screen when the app is in front.
This is a public repo, so fixes, fixtures and examples carry no personal data.

## Filed once, fixed once

One report is one issue, filed once, keyed on its UUID marker.
When looking up existing issues fails, filing stops rather than filing everything again.
A report with incomplete evidence stays pending and is retried, never marked seen.
The listener polls every paired device and every app, and logs every poll, copy and filing outcome as a JSON line.
The listener may start an agent on a filed report, unless whoever is already working on that app is blocked on the same problem.
A dispatched agent may merge its own fix once the pipeline reaches checks-passed, within a rate limit the host Mac's driver sets across apps and agents.
The tools are built for agents first: doctor and status speak JSON with meaningful exit codes.
When an agent needs Igor's help, it links him to a viewer that shows the report with the extra information the agent has gathered.

## Scope

It is not a crash-analytics service: there is no server, no hosted dashboard and no account.
It is not a product for other developers: the repo is public, but outside needs do not shape its defaults, options or roadmap.
It targets Apple platforms, iOS 17 and macOS 14 and later, and its practices name Apple's tools rather than staying platform-neutral.
A generic version for the web may come later, as a separate project.

A change aligns when it gets a device problem to its fixer with more decisive evidence, fixes a shared practice once for every app, or makes filing more exactly-once.
A change should be resisted when it copies BugKit code into an app, makes device filing the default, sends an unscrubbed screenshot or private data to a tracker, or lets the tools guess.
