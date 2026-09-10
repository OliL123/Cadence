#!/usr/bin/env bash
# Build the CHRONICLE skin of the app and publish it to the separate Chronicle
# GitHub Pages repo. One source tree (this one); the skin is chosen with
# --dart-define=CHRONICLE=true, and this script rewrites the built web metadata
# (title / manifest / icons) for Chronicle's own identity.
#
# Usage:  bash tool/deploy_chronicle.sh [/path/to/chronicle/repo]
#   default repo dir: ../chronicle  (a clone of the new GitHub 'chronicle' repo)
set -e
cd "$(dirname "$0")/.."
export PATH="$PATH:/c/src/flutter/bin"

REPO_DIR="${1:-../chronicle}"
BASE_HREF="/chronicle/"      # GitHub Pages serves the repo at /<repo>/
ICONS="tool/chronicle_icons"
BUILD="$(date +%Y%m%d%H%M%S)"
echo "Chronicle build id: $BUILD  →  repo: $REPO_DIR"

MSYS_NO_PATHCONV=1 flutter build web --release \
  --base-href "$BASE_HREF" --dart-define=CHRONICLE=true

W=build/web

# --- Chronicle identity in the built web output -----------------------------
# title + iOS home-screen name + description
sed -i 's#<title>.*</title>#<title>Chronicle</title>#' "$W/index.html"
sed -i 's#content="cadence"#content="Chronicle"#' "$W/index.html"
sed -i 's#<meta name="description" content="[^"]*">#<meta name="description" content="Chronicle — a personal chronicle of tasks.">#' "$W/index.html"
# apple-touch-icon → our 180px seal
sed -i 's#<link rel="apple-touch-icon" href="[^"]*">#<link rel="apple-touch-icon" href="apple-touch-icon.png">#' "$W/index.html"

# manifest: name / colours
sed -i 's#"name": *"[^"]*"#"name": "Chronicle"#' "$W/manifest.json"
sed -i 's#"short_name": *"[^"]*"#"short_name": "Chronicle"#' "$W/manifest.json"
sed -i 's|"background_color": *"[^"]*"|"background_color": "#E7DFC9"|' "$W/manifest.json"
sed -i 's|"theme_color": *"[^"]*"|"theme_color": "#9E2420"|' "$W/manifest.json"
sed -i 's#"description": *"[^"]*"#"description": "Chronicle — a personal chronicle of tasks."#' "$W/manifest.json"

# --- Chronicle icons ---------------------------------------------------------
cp "$ICONS/favicon.png"            "$W/favicon.png"
cp "$ICONS/apple-touch-icon.png"   "$W/apple-touch-icon.png"
cp "$ICONS/Icon-192.png"           "$W/icons/Icon-192.png"
cp "$ICONS/Icon-512.png"           "$W/icons/Icon-512.png"
cp "$ICONS/Icon-maskable-192.png"  "$W/icons/Icon-maskable-192.png"
cp "$ICONS/Icon-maskable-512.png"  "$W/icons/Icon-maskable-512.png"

# --- auto-update stamping (same mechanism as Cadence) ------------------------
sed -i "s/__BUILD_ID__/$BUILD/g" "$W/index.html"
sed -i "s#flutter_bootstrap.js\"#flutter_bootstrap.js?v=$BUILD\"#" "$W/index.html"
sed -i "s#\"main.dart.js\"#\"main.dart.js?v=$BUILD\"#g" "$W/flutter_bootstrap.js"
printf '%s' "$BUILD" > "$W/build.txt"

# --- publish to the Chronicle repo's docs/ -----------------------------------
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "!! $REPO_DIR is not a git repo. Create/clone the 'chronicle' repo there first."
  exit 1
fi
rm -rf "$REPO_DIR/docs" && mkdir -p "$REPO_DIR/docs"
cp -r "$W"/* "$REPO_DIR/docs/"
touch "$REPO_DIR/docs/.nojekyll"

echo "Chronicle published into $REPO_DIR/docs (build $BUILD)."
echo "Now:  cd $REPO_DIR && git add -A && git commit -m \"Deploy $BUILD\" && git push"
