#!/usr/bin/env bash
# Read a session log (JSON Lines: {"type", "t", [wall], [mono], …}) without opening it. EA's `just log-summary`
# and MM's `session-around` / `session-log`, for any app on BugKit's log.
#
#   scripts/log-tool.sh summary <log> [--drop frame,clock]   every line except the noisy types, then their counts
#   scripts/log-tool.sh around  <log> <HH:MM:SS> [secs]      the lines within ±secs (default 10) of a wall time
#   scripts/log-tool.sh at      <log> <t ms> [secs]          the lines within ±secs of a moment in ms since launch,
#                                                            such as a report's session_t_ms
#   scripts/log-tool.sh errors  <log>                        the `error` and `crash_report` lines
#   scripts/log-tool.sh types   <log>                        each event type and how often it occurs
#
# <log> is a file, or a folder, in which case the newest *.jsonl in it (or in its logs/) is read. `around` needs
# the `wall` stamp (SessionLog(clocks: [.wall])), or an older log whose `t` is itself the wall time (MM). A line
# that is not JSON is named once on stderr and counted, never fatal.
set -uo pipefail
cmd=${1:-}; log=${2:-}
[ -n "$cmd" ] && [ -n "$log" ] || { sed -n '2,15p' "$0" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
if [ -d "$log" ]; then
  dir=$log; [ -d "$log/logs" ] && dir=$log/logs
  log=$(\ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
  [ -n "$log" ] || { echo "no *.jsonl in $dir" >&2; exit 2; }
  echo "# $log" >&2
fi
[ -f "$log" ] || { echo "no log at $log" >&2; exit 2; }

# The valid lines, as compact JSON, from one jq pass; each invalid one is named once on stderr, then counted.
valid() {
  jq -rR '. as $l | select(length > 0) | try (fromjson | tojson) catch "# line \(input_line_number) is not JSON: \($l[0:60])"' "$log" \
    | awk '/^# line / { bad++; print > "/dev/stderr"; next } { print } END { if (bad) print "# " bad " line(s) skipped" > "/dev/stderr" }'
}

case "$cmd" in
  summary)
    drop=""
    [ "${3:-}" = "--drop" ] && drop=${4:-}
    valid | jq -nr --arg drop "$drop" '
      ($drop | split(",") | map(select(. != ""))) as $d
      | foreach ((inputs | [.]), null) as $x ({n: {}};
          if $x == null then .done = true
          elif ($x[0].type as $t | $d | index($t)) then .n[$x[0].type | tostring] += 1 | .emit = false
          else .emit = true end;
          if .done then (.n | to_entries | sort_by(.key)[] | "# dropped \(.key): \(.value)")
          elif .emit then $x[0] | tojson else empty end)'
    ;;
  around)
    at=${3:?HH:MM:SS}; secs=${4:-10}
    valid | jq -c --arg at "$at" --argjson secs "$secs" '
      def hms: capture("T(?<h>[0-9]{2}):(?<m>[0-9]{2}):(?<s>[0-9]{2}(\\.[0-9]+)?)") | (.h|tonumber)*3600 + (.m|tonumber)*60 + (.s|tonumber);
      ($at | split(":") | map(tonumber) | .[0]*3600 + .[1]*60 + (.[2] // 0)) as $target
      | (if (.wall|type) == "string" then .wall elif (.t|type) == "string" then .t else null end) as $w
      | select($w != null) | select((($w | hms) - $target) | fabs <= $secs)'
    ;;
  at)
    t=${3:?t in ms}; secs=${4:-10}
    valid | jq -c --argjson t "$t" --argjson secs "$secs" 'select((.t|type) == "number" and ((.t - $t) | fabs) <= $secs * 1000)'
    ;;
  errors)
    valid | jq -c 'select(.type == "error" or .type == "crash_report")'
    ;;
  types)
    valid | jq -r '.type // "(none)"' | sort | uniq -c | sort -rn
    ;;
  *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
