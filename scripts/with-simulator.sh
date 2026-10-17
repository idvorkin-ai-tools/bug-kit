#!/usr/bin/env bash
# Run a command with one named simulator held, so two agents cannot both claim it (#47). The whole run holds a lockf
# lock per simulator name. Inside the lock the named simulator showing as booted can only be a leftover, so the run
# waits only for OTHER booted simulators (one simulator on this Mac at a time), boots this one, and shuts it down on
# exit, pass or fail. Create the command's log files inside the command, so two runs' logs cannot interleave.
#
#   scripts/with-simulator.sh <name> [--wait <seconds>] -- <command…>
#
#   <name>   the simulator's name in `xcrun simctl list devices available`; the newest runtime's wins
#   --wait   how long to wait for the lock, and then for other booted simulators (default 1200)
#   The command runs with SIM_UDID set. Exits 75 when another run held <name>, or another simulator stayed booted,
#   for the whole wait; 2 when no simulator has that name.
set -uo pipefail
usage() { echo "usage: with-simulator.sh <name> [--wait <seconds>] -- <command…>" >&2; exit 2; }
name=${1:-}; [ -n "$name" ] || usage; shift
wait=1200
if [ "${1:-}" = --wait ]; then wait=${2:-}; shift 2 || usage; fi
[ "${1:-}" = -- ] || usage; shift
[ $# -gt 0 ] || usage
SIMCTL=${BUG_KIT_SIMCTL:-xcrun simctl}

if [ -z "${BUG_KIT_SIM_HELD:-}" ]; then
  locks=${BUG_KIT_SIM_LOCKS:-$HOME/tmp/agent/locks}
  mkdir -p "$locks"
  lock="$locks/sim-$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_').lock"
  started=$(mktemp)
  trap 'rm -f "$started"' EXIT
  # -k keeps the file, so a waiter never locks one just removed. lockf itself exits 75 when the wait runs out.
  BUG_KIT_SIM_HELD="$started" lockf -k -t "$wait" "$lock" "$0" "$name" --wait "$wait" -- "$@"
  status=$?
  if [ "$status" = 75 ] && [ ! -s "$started" ]; then
    echo "another run held $name for $wait s; nothing ran" >&2
  fi
  exit "$status"
fi
echo held >"$BUG_KIT_SIM_HELD"

udid=$($SIMCTL list devices available | grep -F -- "    $name (" | tail -1 | grep -oE '[0-9A-F-]{36}')
[ -n "$udid" ] || { echo "no simulator named $name" >&2; exit 2; }
deadline=$((SECONDS + wait))
while others=$($SIMCTL list devices booted | grep -E '\(Booted\)' | grep -v -F "$udid"); [ -n "$others" ]; do
  [ "$SECONDS" -ge "$deadline" ] && { echo "another simulator stayed booted for $wait s; nothing ran: $others" >&2; exit 75; }
  sleep 5
done
trap '$SIMCTL shutdown "$udid" >/dev/null 2>&1' EXIT
$SIMCTL bootstatus "$udid" -b >/dev/null || { echo "could not boot $name ($udid)" >&2; exit 1; }
SIM_UDID=$udid "$@"
