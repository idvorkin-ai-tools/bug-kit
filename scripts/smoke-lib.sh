# shellcheck shell=bash
# Helpers for an app's simulator smoke script, which checks the app's session log after hook-driven launches. Source
# it, then write the app's checks. The rules come from the apps:
# - wait for an event in a log newer than the launch, never for a time (EA);
# - a timeout fails the run, even if a later assertion finds an old result (EA);
# - a run fails on any `error` event, even when the feature under test passed (CG);
# - a scripted flow must log that it finished, or a crash or an early quit passes for success (MM's selftest);
# - simulator data a check moves aside comes back even when the run is cut short (EA's stash);
# - ONLY=<substring> runs just the matching checks (EA).
#
#   source "$BUG_KIT/scripts/smoke-lib.sh"
#   smoke_init "$SIM" com.example.app            # SMOKE_DOCS=<dir> skips simctl's container lookup (tests)
#   check_report() {
#     launch APP_BUG="smoke|the note"            # becomes SIMCTL_CHILD_APP_BUG for the app's launch hook
#     wait_for bug_report 30 || return
#     require_event bug_report 'select(.note == "the note")' "the report has the note"
#     fail_on_errors check_report
#   }
#   run check_report
#   smoke_done                                   # exits 1 if anything failed
#
# Bash 3.2 (macOS /bin/bash) compatible. Needs jq.

SMOKE_SIMCTL=${SMOKE_SIMCTL:-xcrun simctl}
SMOKE_POLL=${SMOKE_POLL:-2}
fail=0
previous_log=""

smoke_init() {  # smoke_init <simulator udid> <bundle id>
  SIM=$1 BUNDLE=$2
  if [ -z "${SMOKE_DOCS:-}" ]; then
    SMOKE_DOCS="$($SMOKE_SIMCTL get_app_container "$SIM" "$BUNDLE" data)/Documents" || {
      echo "FAIL  no container for $BUNDLE on $SIM: install the app first" >&2; exit 2; }
  fi
  LOGS=${SMOKE_LOGS:-$SMOKE_DOCS/logs}
  trap unstash EXIT
}

ok() { echo "ok    $*"; }
not_ok() { echo "FAIL  $*"; fail=1; }

# The newest session log, or nothing on a fresh install.
newest_log() { \ls -t "$LOGS"/*.jsonl 2>/dev/null | head -1; return 0; }

# Terminates the app and launches it with hook variables: `launch APP_BUG=x APP_SHAKE_AFTER=2`. Remembers the newest
# log first, so wait_for accepts only the log this launch writes.
launch() {
  $SMOKE_SIMCTL terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  previous_log=$(newest_log)
  local kv
  for kv in "$@"; do export "SIMCTL_CHILD_$kv"; done
  $SMOKE_SIMCTL launch "$SIM" "$BUNDLE" >/dev/null
  for kv in "$@"; do unset "SIMCTL_CHILD_${kv%%=*}"; done
}

# Waits up to <secs> for an event of <type> in a log newer than the last launch. A timeout fails the run.
wait_for() {  # wait_for <type> <secs>
  local waited=0 f
  while [ "$waited" -lt "$2" ]; do
    f=$(newest_log)
    if [ -n "$f" ] && [ "$f" != "$previous_log" ] && jq -e --arg t "$1" 'select(.type == $t)' "$f" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$SMOKE_POLL"; waited=$((waited + SMOKE_POLL))
  done
  not_ok "timed out after $2 s waiting for $1"
  return 1
}

# The launch's own log, or nothing if the launch wrote none.
this_log() { local f; f=$(newest_log); [ "$f" != "$previous_log" ] && echo "$f"; return 0; }

# Passes when this launch's log has an event of <type>, optionally matching a jq filter; MM's finish marker is
# `require_event selftest_finished`.
require_event() {  # require_event <type> [jq filter] [label]
  local f; f=$(this_log)
  if [ -n "$f" ] && jq -e --arg t "$1" "select(.type == \$t) | ${2:-.}" "$f" >/dev/null 2>&1; then
    ok "${3:-$1}"
  else
    not_ok "${3:-$1}: no $1${2:+ matching $2} in ${f:-a new log}"
  fi
}

# Fails on any `error` event in this launch's log, naming each one's where and message.
fail_on_errors() {  # fail_on_errors [label]
  local f errors; f=$(this_log)
  [ -n "$f" ] || return 0
  errors=$(jq -r 'select(.type == "error") | "\(.where // "?"): \(.message // "")"' "$f" 2>/dev/null)
  if [ -n "$errors" ]; then
    not_ok "${1:-launch}: error events in $(basename "$f")"
    while IFS= read -r e; do echo "      $e"; done <<<"$errors"
  fi
}

# Moves Documents paths aside for a check that needs them absent, and puts them back (also on exit or Ctrl-C).
# A stash an interrupted run left behind is put back first, so the simulator's own data is never lost.
stash() {  # stash <path under Documents>...
  unstash
  local s="$SMOKE_DOCS/.smoke-stash" p
  mkdir -p "$s"
  echo "$*" >"$s/.paths"
  for p in "$@"; do
    mkdir -p "$(dirname "$s/$p")"
    if [ -e "$SMOKE_DOCS/$p" ]; then mv "$SMOKE_DOCS/$p" "$s/$p"; else touch "$s/$p.absent"; fi
  done
}
unstash() {
  local s="$SMOKE_DOCS/.smoke-stash" p
  [ -f "$s/.paths" ] || { rm -rf "$s"; return 0; }
  for p in $(cat "$s/.paths"); do
    if [ -e "$s/$p" ]; then rm -rf "${SMOKE_DOCS:?}/$p"; mv "$s/$p" "$SMOKE_DOCS/$p"
    elif [ -e "$s/$p.absent" ]; then rm -rf "${SMOKE_DOCS:?}/$p"; fi
  done
  rm -rf "$s"
}

# Runs a check unless ONLY is set and does not match its name and arguments.
run() { if [ -z "${ONLY:-}" ] || [[ "$*" == *"$ONLY"* ]]; then "$@"; fi; }

smoke_done() {
  if [ "$fail" = 0 ]; then echo "smoke: all passed"; else echo "smoke: FAILED"; fi
  exit "$fail"
}
