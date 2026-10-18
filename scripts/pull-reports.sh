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
# With CloudKit configured as the listener has it (cloudkit_config naming a JSON file, or an inline "cloudkit" block;
# app, container and environment) it also reads CloudKit (#66), read-only, through the same signed reader the
# listener uses, into its own cache (<root>/.cloudkit-check; the listener's inbox is the listener's): one
# `new <app> cloudkit <reported_at> <note>` line per report whose `bug-id:`/`bug:` marker is in no issue; an
# unreadable CloudKit exits 2. When the listener's status.json says its last poll is older than three poll intervals,
# a check that would read clean exits 3 instead, so a quiet check cannot hide a dead listener.
#
# An app's "app_group" (as in the listener) makes every copy read that App Group's container instead of the app's.
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
cloud=""
if [ "$check" = 1 ]; then
  if jq -e 'has("cloudkit_config")' "$CONFIG" >/dev/null; then
    cloud_config=$(jq -r '.cloudkit_config' "$CONFIG")
    cloud_config=${cloud_config/#\~/$HOME}
    cloud=$(jq -ec . "$cloud_config" 2>/dev/null) || cloud="{}"
  elif jq -e 'has("cloudkit")' "$CONFIG" >/dev/null; then
    cloud=$(jq -c '.cloudkit' "$CONFIG")
    cloud_config="the \"cloudkit\" block in $CONFIG"
  fi
  if [ -n "$cloud" ]; then
    if ! cloud=$(jq -ec 'select(type == "object" and ([.app, .container, .environment] | all(type == "string")))' \
      <<<"$cloud"); then
      echo "could not read the CloudKit config ($cloud_config): it needs app, container and environment" >&2
      exit 2
    fi
    cloud_app=$(jq -r .app <<<"$cloud")
    cloud_app=${cloud_app/#\~/$HOME}
  fi
fi

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
[ -s "$tmp/devices" ] || { echo "no paired iPhone or iPad"; [ "$check" = 1 ] || exit 0; }

apps=$(jq -r --arg only "$only" '.apps[] | select($only == "" or .name == $only)
  | [.name, .bundle, (.tracker.kind // "none"), (.tracker.repo // "-"), (.app_group // "-"),
     ((.pull_extra // []) | join(","))] | @tsv' "$CONFIG")
[ -n "$apps" ] || { echo "no app named '$only' in $CONFIG" >&2; exit 2; }

copy() {  # copy <udid> <bundle> <source under the container> <destination>
  local domain=appDataContainer id=$2
  [ "$group" = - ] || { domain=appGroupDataContainer; id=$group; }
  xcrun devicectl device copy from --device "$1" --domain-type "$domain" --domain-identifier "$id" \
    --source "$3" --destination "$4" --timeout 90 >/dev/null 2>"$tmp/copy-err"
}

ISSUE_LIMIT=10000  # the listener's cap
new_total=0
lookup_failed=0
while IFS=$'\t' read -r app bundle tracker repo group extra; do
  markers=""
  if [ "$check" = 1 ] && [ "$tracker" = github ]; then
    if ! issues=$(gh issue list -R "$repo" --state all --limit "$ISSUE_LIMIT" --json body 2>"$tmp/gh-err"); then
      echo "$app: could not read $repo's issues ($(tail -1 "$tmp/gh-err")); not counting its reports" >&2
      lookup_failed=1
      continue
    fi
    # A full page may have cut off older issues, so its markers aren't the complete list (as in the listener).
    if [ "$(jq length <<<"$issues")" -ge "$ISSUE_LIMIT" ]; then
      echo "$app: $repo has $ISSUE_LIMIT issues or more, past what one read covers; not counting its reports" >&2
      lookup_failed=1
      continue
    fi
    markers=$(jq -r '.[].body' <<<"$issues" | grep -o -E 'bug(-id)?:[0-9A-Za-z:.-]*' || true)
    printf '%s\n' "$markers" >"$tmp/markers-$app"
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
        # The same report may also wait in CloudKit (mirrored delivery): list it once, by id, else by time.
        id=$(jq -r '.id // empty' <<<"$line" 2>/dev/null)
        if [ -n "$id" ]; then echo "$app id:$id"; else echo "$app at:$at"; fi >>"$tmp/listed"
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

if [ -n "$cloud" ]; then
  cache="$ROOT/.cloudkit-check"
  mkdir -p "$cache"
  perl -e 'alarm 180; exec @ARGV' "$cloud_app/Contents/MacOS/BugKitCloudReader" \
    --container "$(jq -r .container <<<"$cloud")" --inbox "$cache" \
    --environment "$(jq -r .environment <<<"$cloud")" >"$tmp/cloud.out" 2>"$tmp/cloud.err"
  cloud_status=$?
  synced=$(jq -c 'select(.event == "cloudkit_sync" and .ok == true)' "$tmp/cloud.out" 2>/dev/null)
  if [ "$cloud_status" != 0 ] || [ -z "$synced" ]; then
    why=$(cat "$tmp/cloud.out" "$tmp/cloud.err" 2>/dev/null | tail -1 | cut -c1-160)
    echo "could not read CloudKit (exit $cloud_status: $why); not counting its reports" >&2
    lookup_failed=1
  else
    for report in "$cache"/*/report.json; do
      [ -f "$report" ] || continue
      IFS=$'\t' read -r bundle id at note < <(jq -r '[.bundle // "", .id // "", .reported_at // "",
        ((.note // "") | split("\n") | map(select(test("\\S"))) | (.[0] // "") | .[0:90])] | @tsv' "$report")
      app=$(awk -F'\t' -v b="$bundle" '$2 == b && $3 == "github" { print $1; exit }' <<<"$apps")
      [ -n "$app" ] && [ -f "$tmp/markers-$app" ] || continue
      grep -q -x -F -e "bug-id:$id" -e "bug:$at" "$tmp/markers-$app" && continue
      grep -q -x -F -e "$app id:$id" -e "$app at:$at" "$tmp/listed" 2>/dev/null && continue  # already listed
      new_total=$((new_total + 1))
      echo "new $app cloudkit $at $note"
    done
  fi
fi

if [ "$check" = 1 ]; then
  [ "$lookup_failed" = 1 ] && exit 2
  if [ "$new_total" -gt 0 ]; then echo "$new_total unfiled report(s): run listener/bug-listener --once"; exit 1; fi
  echo "no unfiled reports"
  if [ -f "$ROOT/status.json" ]; then
    last=$(jq -r '.last_poll_completed // empty' "$ROOT/status.json" 2>/dev/null)
    every=$(jq -r 'if (.poll_seconds | type) == "number" and .poll_seconds > 0 then .poll_seconds | ceil
                   else 300 end' "$ROOT/status.json" 2>/dev/null)
    at=$(jq -rn --arg t "$last" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | floor' 2>/dev/null)
    [[ "$every" =~ ^[0-9]+$ ]] || every=300  # a malformed status.json must not abort the check (exit 1 means "new")
    [[ "$at" =~ ^[0-9]+$ ]] || at=0
    if [ $(( $(date +%s) - at )) -gt $(( 3 * every )) ]; then
      echo "but the listener's last poll was ${last:-never}: reports waiting for it are not counted; start it" \
        "(docs/ops/listener.md)"
      exit 3
    fi
  fi
fi
