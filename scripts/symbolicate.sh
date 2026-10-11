#!/usr/bin/env bash
# Symbolicates a MetricKit crash or hang payload (Documents/crashes/<stamp>.json, from BugKit's CrashReports) against
# the dSYMs of the build that crashed, normally the last device build. Prints the cause, then each frame of the
# attributed thread as "binary  symbol (file:line)" for the app's own binaries and "binary +offset (system)" for the
# rest. From EA's scripts/symbolicate.sh, generalized to any app and any number of dSYMs (app, extensions, frameworks).
#
#   scripts/symbolicate.sh <crash.json> <App.app.dSYM | folder holding *.dSYM>
#   scripts/symbolicate.sh crashes/20261010-150000.json Build/Build/Products/Debug-iphoneos
#
# Frames are matched to a dSYM by binary UUID, so a dSYM from another build never gives a wrong symbol: its frames
# print as "(no dSYM)" instead.
set -euo pipefail
file=${1:?usage: symbolicate.sh <crash.json> <dSYM or folder>}
where=${2:?usage: symbolicate.sh <crash.json> <dSYM or folder>}
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

# "<UUID> <DWARF binary>" for every dSYM, upper-case UUIDs.
dsyms=()
case "$where" in
  *.dSYM | *.dSYM/) dsyms=("${where%/}") ;;
  *) while IFS= read -r d; do dsyms+=("$d"); done < <(find "$where" -maxdepth 1 -name '*.dSYM' 2>/dev/null) ;;
esac
[ "${#dsyms[@]}" -gt 0 ] || { echo "no .dSYM in $where: build for the device first" >&2; exit 2; }
table=$(for d in "${dsyms[@]}"; do
  for bin in "$d"/Contents/Resources/DWARF/*; do
    dwarfdump --uuid "$bin" | awk -v b="$bin" '{print toupper($2), b}'
  done
done)
echo "dSYMs: $(awk '{print $1}' <<<"$table" | tr '\n' ' ')"

jq -r '
  (.crashDiagnostics // []) + (.hangDiagnostics // []) | .[] |
  "cause: exception \(.diagnosticMetaData.exceptionType // "-") signal \(.diagnosticMetaData.signal // "-") reason \((.diagnosticMetaData.terminationReason // "-" | gsub("[\r\n]+"; " ")))",
  (.callStackTree.callStacks[] | select(.threadAttributed == true) | .. | objects | select(has("address")) |
    "frame \(.binaryName // "?") \(.binaryUUID // "-") \(.offsetIntoBinaryTextSegment // 0)")' "$file" |
while read -r kind name uuid off rest; do
  if [ "$kind" = cause: ]; then echo "$kind $name $uuid $off $rest"; continue; fi
  bin=$(awk -v u="$(tr a-z A-Z <<<"$uuid")" '$1 == u {print $2; exit}' <<<"$table")
  if [ -n "$bin" ]; then
    # The offset is from the binary's __TEXT start. `atos -l 0x0 <offset>` (the older recipe) prints the bare
    # address back, so give atos the real start and start + offset.
    text=$(otool -l "$bin" | awk '/segname __TEXT$/ {getline; print $2; exit}')
    addr=$(printf '0x%x' $((text + off)))
    echo "  $name  $(atos -o "$bin" -arch arm64 -l "$text" "$addr" 2>/dev/null || echo "+$off")"
  elif grep -q -i "/$name\$" <<<"$table"; then
    echo "  $name  +$off (no dSYM for this build: $uuid)"
  else
    echo "  $name  +$off (system)"
  fi
done
