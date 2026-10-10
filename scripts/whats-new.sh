#!/usr/bin/env bash
# What's new, made at build time (CG story 148): the app's last month of `git log` plus its stories' summaries,
# written as the JSON the app bundles and `WhatsNewFeed.decode` reads. Never fails the build: without git history
# or a compiler the app gets an empty feed and says "nothing new".
#
#   scripts/whats-new.sh <out.json> [--repo <dir>] [--stories <dir>] [--path <git pathspec>] [--base-url <url>] [--days N]
#
#   --repo      the app's checkout (default: the current directory's git root)
#   --stories   its user stories, "### User Story NNN:" + "- **Summary:**" (default: <repo>/docs/stories)
#   --path      only commits touching this path (CG: native)
#   --base-url  where the stories folder is on the web, for each change's link, e.g.
#               https://github.com/<owner>/<repo>/blob/main/docs/stories/
#
# As an Xcode (XcodeGen) build phase, with BugKit checked out by SwiftPM:
#   script: '"$BUILD_DIR/../../SourcePackages/checkouts/bug-kit/scripts/whats-new.sh" \
#     "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/whats-new.json" --repo "$SRCROOT" --base-url "<url>"'
set -uo pipefail
out=${1:?usage: whats-new.sh <out.json> [options]}
shift
repo="" stories="" pathspec="" base="" days=30
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --stories) stories=$2; shift 2 ;;
    --path) pathspec=$2; shift 2 ;;
    --base-url) base=$2; shift 2 ;;
    --days) days=$2; shift 2 ;;
    *) echo "whats-new: unknown option $1" >&2; exit 2 ;;
  esac
done
kit=$(cd "$(dirname "$0")/.." && pwd)
repo=${repo:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
stories=${stories:-$repo/docs/stories}
work=${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}/bugkit-whats-new}
mkdir -p "$work" "$(dirname "$out")"
empty() { echo "whats-new: $1; writing an empty feed" >&2; printf '{"days":[],"generated":""}\n' >"$out"; exit 0; }

core="$kit/Sources/BugKit/WhatsNew.swift"
main="$kit/Tools/whats-new/main.swift"
tool="$work/whats-new-tool"
if [ ! -x "$tool" ] || [ "$core" -nt "$tool" ] || [ "$main" -nt "$tool" ]; then
  # A host build: Xcode's environment points SDKROOT and the architectures at the device or the simulator.
  env -i PATH=/usr/bin:/bin HOME="$HOME" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} \
    xcrun --sdk macosx swiftc -module-name WhatsNewTool -o "$tool" "$core" "$main" >&2 || empty "swiftc failed"
fi
git -C "$repo" log --since="$((days + 1)).days" --format='%h%x1f%cI%x1f%s%x1f%b%x1e' -- ${pathspec:+"$pathspec"} \
  >"$work/log.txt" 2>/dev/null || empty "no git history"
"$tool" "$work/log.txt" "$stories" "$out" "$base" "$days" || empty "the tool failed"
