#!/usr/bin/env bash
# An event stream for an agent's Monitor: runs `pull-reports.sh --check` every minute and prints one line per new
# report, each report once, and nothing while nothing is new. A Monitor wakes the agent only when there is something
# to file, which is cheaper than a /loop that runs the model every few minutes to look (EA scripts/bugs-monitor.sh).
#
#   scripts/bugs-monitor.sh [app] [--every 60]
#   Monitor(command: "<bug-kit>/scripts/bugs-monitor.sh exercise-analyzer", persistent: true)
#
# Lines:
#   new <app> <device> <reported_at> <note>   a report with no issue yet, printed once per app and reported_at
#   check_failed <reason>                      the check exited 2 (devicectl, or the issue lookup), printed once
#                                              until a check succeeds again, so a broken check is not silence
#   check_ok                                   the first good check after a check_failed
#   listener_stale <line>                      the check exited 3: clean, but the listener has stopped polling;
#                                              printed once until it polls again, then listener_ok
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=${BUG_KIT_CHECK:-$HERE/pull-reports.sh}
app="" every=60 rounds=-1  # --rounds N stops after N checks (tests)
while [ $# -gt 0 ]; do
  case $1 in
    --every) every=$2; shift ;;
    --rounds) rounds=$2; shift ;;
    -*) echo "usage: bugs-monitor.sh [app] [--every seconds]" >&2; exit 2 ;;
    *) app=$1 ;;
  esac
  shift
done

seen=" " failing=0 stale=0
errf=$(mktemp)
trap 'rm -f "$errf"' EXIT
while [ "$rounds" != 0 ]; do
  out=$("$CHECK" --check ${app:+"$app"} 2>"$errf"); rc=$?
  if [ "$rc" = 3 ]; then
    [ "$stale" = 0 ] && echo "listener_stale $(grep -m1 "listener's last poll" <<<"$out" | cut -c1-160)"
    stale=1
  elif [ "$rc" != 2 ]; then
    [ "$stale" = 1 ] && echo "listener_ok"
    stale=0
  fi
  if [ "$rc" = 2 ]; then
    [ "$failing" = 0 ] && echo "check_failed $(tail -1 "$errf" | cut -c1-160)"
    failing=1
  else
    [ "$failing" = 1 ] && echo "check_ok"
    failing=0
    while IFS= read -r line; do
      case "$line" in
        "new "*)
          key=$(awk '{print $2 "@" $4}' <<<"$line")
          case "$seen" in *" $key "*) ;; *) seen="$seen$key "; echo "$line" ;; esac
          ;;
      esac
    done <<<"$out"
  fi
  rounds=$((rounds - 1))
  [ "$rounds" = 0 ] || sleep "$every"
done
