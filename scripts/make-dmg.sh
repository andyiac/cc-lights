#!/usr/bin/env bash
# Build a distributable .dmg containing the app, a drag-to-Applications
# shortcut, the cc-statusctl CLI, and a short install note.
# Requires the packaged app in dist/ (run `make bundle` first).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CC Light"
DIST_DIR="dist"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
CLI_PATH="${DIST_DIR}/cc-statusctl"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing ${APP_PATH}. Run 'make bundle' first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
VOL_NAME="${APP_NAME} ${VERSION}"
DMG_PATH="${DIST_DIR}/${APP_NAME// /-}-${VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

# Contents laid out inside the DMG window.
cp -R "${APP_PATH}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

if [[ -f "${CLI_PATH}" ]]; then
  mkdir -p "${STAGE}/CLI (optional)"
  cp "${CLI_PATH}" "${STAGE}/CLI (optional)/cc-statusctl"
  cat > "${STAGE}/CLI (optional)/Install CLI.command" <<'CMD'
#!/bin/bash
# Install the cc-statusctl helper into ~/bin.
set -e
cd "$(dirname "$0")"
mkdir -p "$HOME/bin"
cp cc-statusctl "$HOME/bin/cc-statusctl"
chmod +x "$HOME/bin/cc-statusctl"
echo "Installed cc-statusctl to $HOME/bin/cc-statusctl"
echo "Make sure $HOME/bin is on your PATH."
CMD
  chmod +x "${STAGE}/CLI (optional)/Install CLI.command"
fi

cat > "${STAGE}/Install.txt" <<TXT
${APP_NAME} ${VERSION}

1. Drag "${APP_NAME}.app" onto the Applications folder.
2. Launch it from Applications. It runs as a menu bar app (no Dock icon).

The app is ad-hoc signed, so the first launch may need:
  Right-click the app > Open, then confirm.

Optional: install the cc-statusctl CLI by running
"CLI (optional)/Install CLI.command".
TXT

rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}" >/dev/null

echo "Built ${DMG_PATH}"
