# Operating iOS apps from a Mac, with agents

This folder describes how Exercise Analyzer (EA), Context Grabber's native app (CG) and Magic Monitor (MM) are built, deployed, tested and debugged on real devices by coding agents that cannot see the screen. It is written generally: each page names where a rule came from, and every device id, team id and account is a placeholder.

| Page | What it covers |
|---|---|
| [logging.md](logging.md) | The event catalogue, `ui` with `from:`, the logic version in `session_start`, status screens, a companion's events |
| [pulling-and-filing.md](pulling-and-filing.md) | Getting logs, reports and crashes off the phone and iPad; filing each report once; devicectl quirks |
| [runners.md](runners.md) | The listener, Monitor versus `/loop`, background builds, the no-mistakes pipeline, one agent at a time |
| [deploying.md](deploying.md) | Build once, install on the phone, the iPad and the watch; the signing lock; the BUILD SUCCEEDED rule; error 10002 |
| [signing.md](signing.md) | Keeping automatic signing working: which builds need the Xcode account, how to check, new devices, new capabilities |
| [simulators.md](simulators.md) | One named simulator at a time, launch hooks, privacy grants, editing preferences behind cfprefsd, erase needs shutdown |
| [test-ladder.md](test-ladder.md) | Host, simulator and device rungs, and naming the rung |
| [crashes-and-tools.md](crashes-and-tools.md) | Symbolicating MetricKit payloads, `.ips` reports, Instruments from the command line |

## Scripts

All three scripts are configured through `~/.config/bug-kit/apps.json`, the listener's file.

- `scripts/pull-reports.sh [--check] [app]`: pulls logs, reports and crash files from every device.
- `scripts/deploy-all.sh <app> [--only …] [--register dev] [--watch] [--dry-run]`: builds once under the signing lock and installs on every device.
- `scripts/whats-new.sh <out.json> --repo … --base-url …`: the What's new build phase.
- `scripts/log-tool.sh summary|around|at|errors|types <log>`: reads a session log without opening it. It is EA's `log-summary` plus MM's `session-around`.

## Sources

The rules come from these places:
- the apps' justfiles, `scripts/`, DEBUGGING.md, TESTING.md and AGENTS.md;
- chop-conventions `deployment/ios-device-signing.md` (PR #238) and `dev-inner-loop/` (PR #239);
- the mac-driver README;
- the agents' session notes from 2026-09 and 2026-10.
