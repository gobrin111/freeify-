#!/usr/bin/env bash
# Finds the iOS build for a commit, waits for it, and saves its unsigned IPA on Windows.
#   fetch_ipa.sh [commit]          (default: HEAD)
# Saves to $FREEIFY_BUILDS_DIR/<run number>/Freeify-unsigned.ipa and Freeify-latest.ipa,
# keeping the five newest numbered builds. Exit codes: 0 saved, 1 build failed or bad IPA,
# 2 no build for that commit, 3 setup problem (gh, repo).
set -euo pipefail

REPO=gobrin111/freeify-
WORKFLOW=ios-build.yml
DEST=${FREEIFY_BUILDS_DIR:-/mnt/c/Users/Qi/Freeify-builds}
KEEP=5

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
sha=$(git rev-parse "${1:-HEAD}")
gh auth status >/dev/null 2>&1 || { echo "gh is not signed in: run  gh auth login --hostname github.com --web"; exit 3; }

# Runs start a few seconds after a push; look for up to ~60 s.
run=""
for _ in $(seq 12); do
  run=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$sha" --limit 1 \
        --json databaseId --jq '.[0].databaseId // empty')
  [ -n "$run" ] && break
  sleep 5
done
if [ -z "$run" ]; then
  echo "No build for ${sha:0:7}. Only changes to Freeify/, Freeify.xcodeproj/, Tests/, or the"
  echo "workflow start one; or the commit isn't pushed. Manual build:"
  echo "  gh workflow run $WORKFLOW --repo $REPO --ref main"
  exit 2
fi

number=$(gh run view "$run" --repo "$REPO" --json number --jq .number)
url=$(gh run view "$run" --repo "$REPO" --json url --jq .url)
echo "Build #$number for ${sha:0:7}: $url"
gh run watch "$run" --repo "$REPO" --interval 30 >/dev/null 2>&1 || true
conclusion=$(gh run view "$run" --repo "$REPO" --json conclusion --jq .conclusion)
if [ "$conclusion" != "success" ]; then
  echo "Build #$number: $conclusion. Failed step log (last 60 lines):"
  gh run view "$run" --repo "$REPO" --log-failed 2>/dev/null | tail -60
  exit 1
fi

target="$DEST/$number"
rm -rf "$target" && mkdir -p "$target"
gh run download "$run" --repo "$REPO" --name "Freeify-unsigned-$number" --dir "$target"
ipa="$target/Freeify-unsigned.ipa"
# Zip integrity and the app's version, with Python's standard library (no unzip needed).
# The workflow sets the build number to the run number; check the package says so.
read -r version build < <(python3 - "$ipa" <<'EOF'
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as ipa:
    if ipa.testzip() is not None:
        print("? corrupt"); sys.exit()
    p = plistlib.loads(ipa.read("Payload/Freeify.app/Info.plist"))
print(p.get("CFBundleShortVersionString", "?"), p.get("CFBundleVersion", "?"))
EOF
) || { echo "Downloaded IPA is not a valid app package: $ipa"; exit 1; }
if [ "$build" != "$number" ]; then
  echo "IPA build number $build doesn't match run #$number: $ipa"
  exit 1
fi

windows() { wslpath -w "$1" 2>/dev/null || echo "$1"; }
echo "Saved Freeify $version ($build), $(du -h "$ipa" | cut -f1):"
echo "  $(windows "$ipa")"
# Freeify-latest.ipa only ever moves forward, so fetching an older build can't replace it.
newest=$(ls -1 "$DEST" | grep -E '^[0-9]+$' | sort -n | tail -1)
if [ "$number" = "$newest" ]; then
  cp "$ipa" "$DEST/Freeify-latest.ipa"
  echo "  $(windows "$DEST/Freeify-latest.ipa")  (same file, always the newest)"
fi
ls -1 "$DEST" | grep -E '^[0-9]+$' | sort -n | head -n -"$KEEP" \
  | while read -r old; do rm -rf "${DEST:?}/$old"; done
