#!/usr/bin/env bash
# Build the Android APK and publish it as the `apk` GitHub release, replacing
# the previous one. The web app's download button links there
# (lib/platform/apk_download_web.dart). Keeping the APK out of git stops every
# deploy adding ~67 MB to the repo.
# Needs the GitHub CLI, logged in once:  gh auth login
# Usage:  bash tool/release_apk.sh
set -e
cd "$(dirname "$0")/.."
export PATH="$PATH:/c/src/flutter/bin:/c/Program Files/GitHub CLI"

flutter build apk --release
APK=build/app/outputs/flutter-apk/cadence.apk
cp build/app/outputs/flutter-apk/app-release.apk "$APK"

REPO=OliL123/Cadence
NOTE="Cadence for Android, built $(date '+%Y-%m-%d %H:%M') from $(git rev-parse --short HEAD)."
if gh release view apk --repo "$REPO" >/dev/null 2>&1; then
  gh release upload apk "$APK" --repo "$REPO" --clobber
  gh release edit apk --repo "$REPO" --notes "$NOTE"
else
  gh release create apk "$APK" --repo "$REPO" --title "Cadence for Android" --notes "$NOTE"
fi
echo "APK published: https://github.com/$REPO/releases/download/apk/cadence.apk"
