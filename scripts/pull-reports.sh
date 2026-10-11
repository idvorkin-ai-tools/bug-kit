#!/usr/bin/env bash
# Pulls each app's session logs, bug reports and crash files off every reachable iPhone and iPad, into the same tree
# the listener uses: ~/tmp/agent/bugs/<app>/<device>/{logs,bugs.jsonl,bugs,crashes}. The by-hand `just pull-logs`
# for all apps and all devices at once (EA pull-logs, CG scripts/native/pull-logs.sh after CG PR #241).
#
#   scripts/pull-reports.sh                 # every app in ~/.config/bug-kit/apps.json, every device
#   scripts/pull-reports.sh context-grabber # one app
#   scripts/pull-reports.sh --check [app]   # bugs.jsonl only; print unfiled reports, exit 1 when there are any
#
# --check is bugs-check: one stable line per unfiled report, `new <app> <device> <reported_at> <note>`, so a
# Monitor or a loop can parse it (CG's bugs-monitor stopped matching when the line format changed). It compares
# against the `<!-- bug:<reported_at> -->` markers in the app's GitHub issues; if that lookup fails it says so and
# exits 2 rather than calling everything new (CG 6fed157). An unreachable device is named, not a failure.
#
# An app's "pull_extra" list names more container paths to copy, each into <device>/<its last component>: EA's
# watch files wait in Documents/Inbox/com.apple.watchconnectivity until the app takes them.
#
# Devices: `xcrun devicectl list devices`, physical iPhones and iPads, named by model (iphone-17-pro). No ids are
# kept anywhere. Config: BUG_KIT_CONFIG (default ~/.config/bug-kit/apps.json), the listener's file.
set -uo pipefail
CONFIG=${BUG_KIT_CONFIG:-$HOME/.config/bug-kit/apps.json}
ROOT=${BUG_KIT_ROOT:-$HOME/tmp/agent/bugs}
check=0
[ "${1:-}" = "--check" ] && { check=1; shift; }
only=${1:-}
[ -f "$CONFIG" ] || { echo "no config at $CONFIG (copy listener/apps.example.json)" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if ! xcrun devicectl list devices --json-output "$tmp/devices.json" >/dev/null 2>"$tmp/err"; then
  echo "devicectl list devices failed: $(tail -2 "$tmp/err")" >&2
  exit 2
fi
# "<dir> <id> <type>" per physical iPhone/iPad; the dir is the model's slug, -b for a second of the same model.
jq -r '[.result.devices[] | select(.hardwareProperties.reality == "physical"
         and (.hardwareProperties.deviceType == "iPhone" or .hardwareProperties.deviceType == "iPad"))]
       | map({id: .identifier, type: .hardwareProperties.deviceType,
              dir: ((.hardwareProperties.marketingName // .hardwareProperties.productType)
                    | ascii_downcase | gsub("[^a-z0-9]+"; "-") | ltrimstr("-") | rtrimstr("-"))})
       | reduce .[] as $d ([]; . + [$d + {dir: (if any(.[]; .dir == $d.dir) then $d.dir + "-b" else $d.dir end)}])
       | .[] | "\(.dir) \(.id) \(.type)"' "$tmp/devices.json" >"$tmp/devices"
[ -s "$tmp/devices" ] || { echo "no paired iPhone or iPad"; exit 0; }

apps=$(jq -r --arg only "$only" '.apps[] | select($only == "" or .name == $only)
  | [.name, .bundle, (.tracker.kind // "none"), (.tracker.repo // "-"), ((.pull_extra // []) | join(","))] | @tsv' "$CONFIG")
[ -n "$apps" ] || { echo "no app named '$only' in $CONFIG" >&2; exit 2; }

copy() {  # copy <udid> <bundle> <source under the container> <destination>
  xcrun devicectl device copy from --device "$1" --domain-type appDataContainer --domain-identifier "$2" \
    --source "$3" --destination "$4" --timeout 90 >/dev/null 2>"$tmp/copy-err"
}

new_total=0
lookup_failed=0
while IFS=$'\t' read -r app bundle tracker repo extra; do
  markers=""
  if [ "$check" = 1 ] && [ "$tracker" = github ]; then
    if ! bodies=$(gh issue list -R "$repo" --state all --limit 1000 --json body --jq '.[].body' 2>"$tmp/gh-err"); then
      echo "$app: could not read $repo's issues ($(tail -1 "$tmp/gh-err")); not counting its reports" >&2
      lookup_failed=1
      continue
    fi
    markers=$(grep -o 'bug:[0-9TZ:.-]*' <<<"$bodies" || true)
  fi
  while read -r dir udid type; do
    out="$ROOT/$app/$dir"
    mkdir -p "$out"
    if ! copy "$udid" "$bundle" Documents/bugs.jsonl "$out/bugs.jsonl"; then
      if grep -q -i -E 'not.*(found|exist)|No such file' "$tmp/copy-err"; then
        echo "== $app / $dir: no bugs.jsonl (no report yet, or the app is not installed)"
      else
        echo "== $app / $dir: not reachable ($(grep -m1 -i error "$tmp/copy-err" | cut -c1-120))"
        continue
      fi
    fi
    if [ "$check" = 1 ]; then
      [ -f "$out/bugs.jsonl" ] || continue
      [ "$tracker" = github ] || { echo "== $app / $dir: tracker $tracker, --check compares GitHub only"; continue; }
      n=0
      while IFS= read -r line; do
        n=$((n + 1))
        [ -n "$line" ] || continue
        # An older app's note with a raw newline splits a report over two lines, neither valid JSON: name it, skip it.
        if ! at=$(jq -r '.reported_at // empty' <<<"$line" 2>/dev/null); then
          echo "skip $app $dir line $n: not JSON (${line:0:60})" >&2
          continue
        fi
        [ -n "$at" ] || { echo "skip $app $dir line $n: no reported_at" >&2; continue; }
        grep -q -F "bug:$at" <<<"$markers" && continue
        new_total=$((new_total + 1))
        note=$(jq -r '.note // ""' <<<"$line" | awk 'NF { print; exit }' | cut -c1-90)
        echo "new $app $dir $at $note"
      done <"$out/bugs.jsonl"
      continue
    fi
    copy "$udid" "$bundle" Documents/logs "$out/logs" || echo "   $dir: logs not copied ($(grep -m1 -i error "$tmp/copy-err" | cut -c1-100))"
    copy "$udid" "$bundle" Documents/bugs "$out/bugs" || true        # absent until the first report
    copy "$udid" "$bundle" Documents/crashes "$out/crashes" || true  # absent until the first crash
    # The app's own extra folders, e.g. the WatchConnectivity inbox where files from the watch wait (EA #197).
    for path in ${extra//,/ }; do
      copy "$udid" "$bundle" "$path" "$out/$(basename "$path")" \
        || echo "   $dir: $path not copied ($(grep -m1 -i error "$tmp/copy-err" | cut -c1-100))"
    done
    echo "== $app / $dir: $(\ls "$out/logs" 2>/dev/null | wc -l | tr -d ' ') logs, $(wc -l <"$out/bugs.jsonl" 2>/dev/null | tr -d ' ' || echo 0) reports, $(\ls "$out/crashes" 2>/dev/null | wc -l | tr -d ' ') crash files in ${out/#$HOME/\~}"
    tail -3 "$out/bugs.jsonl" 2>/dev/null | jq -c '{reported_at, note: (.note[0:70]), log, screen}' 2>/dev/null || true
  done <"$tmp/devices"
done <<<"$apps"

if [ "$check" = 1 ]; then
  [ "$lookup_failed" = 1 ] && exit 2
  if [ "$new_total" -gt 0 ]; then echo "$new_total unfiled report(s): run listener/bug-listener --once"; exit 1; fi
  echo "no unfiled reports"
fi
