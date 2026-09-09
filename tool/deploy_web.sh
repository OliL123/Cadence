#!/usr/bin/env bash
# Build the web app, stamp a unique build id for auto-update, cache-bust the
# JS load chain, and copy everything into docs/ for GitHub Pages.
# Usage:  bash tool/deploy_web.sh
set -e
cd "$(dirname "$0")/.."
export PATH="$PATH:/c/src/flutter/bin"

BUILD="$(date +%Y%m%d%H%M%S)"
echo "Build id: $BUILD"

MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/Cadence/"

# Stamp the build id and cache-bust the entry chain so a new deploy is fetched
# fresh (GitHub Pages serves assets with a 10-minute cache otherwise).
sed -i "s/__BUILD_ID__/$BUILD/g" build/web/index.html
sed -i "s#flutter_bootstrap.js\"#flutter_bootstrap.js?v=$BUILD\"#" build/web/index.html
sed -i "s#\"main.dart.js\"#\"main.dart.js?v=$BUILD\"#g" build/web/flutter_bootstrap.js
printf '%s' "$BUILD" > build/web/build.txt

# Publish to docs/, preserving the bundled APK.
[ -f docs/cadence.apk ] && cp docs/cadence.apk /tmp/cadence.apk.keep
rm -rf docs && mkdir -p docs
cp -r build/web/* docs/
touch docs/.nojekyll
[ -f /tmp/cadence.apk.keep ] && cp /tmp/cadence.apk.keep docs/cadence.apk

echo "docs/ ready (build $BUILD)"
