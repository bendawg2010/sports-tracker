#!/usr/bin/env bash
#
# Sports Tracker installer
# ------------------------
# What this script does, in plain English:
#
#   1. Downloads the latest signed (well, unsigned — see below) release of
#      Sports Tracker from GitHub.
#   2. Unzips it into /Applications, replacing any older copy that's there.
#   3. Removes the "com.apple.quarantine" flag macOS slaps on anything you
#      download from the internet. That flag is what triggers the
#      "Apple cannot check this app for malicious software" popup. Removing
#      it tells Gatekeeper "I trust this binary" — which is exactly what
#      you'd be doing manually if you right-clicked the app and chose Open.
#   4. Tells you it worked.
#
# Why is the quarantine flag a thing? Apple charges $100/year for a Developer
# Program membership that lets you sign apps so this warning never appears.
# Sports Tracker is a free hobby project, so it doesn't pay that toll. The
# warning is a paperwork problem, not a malware problem. The full source is
# on GitHub: https://github.com/bendawg2010/sports-tracker
#
# Don't trust this script? Read it. It's 60 lines of bash. Or build the app
# yourself from source — instructions in INSTALL.md.
#

set -euo pipefail

REPO="bendawg2010/sports-tracker"
APP_NAME="SportsTracker.app"
ZIP_NAME="SportsTracker.app.zip"
INSTALL_DIR="/Applications"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ZIP_NAME}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Downloading Sports Tracker (latest release)..."
if ! curl -fL --progress-bar -o "$TMP_DIR/$ZIP_NAME" "$DOWNLOAD_URL"; then
  echo "Download failed. Check your internet connection and try again."
  echo "Or download manually: https://github.com/${REPO}/releases/latest"
  exit 1
fi

echo "==> Unpacking..."
unzip -q -o "$TMP_DIR/$ZIP_NAME" -d "$TMP_DIR"

if [ ! -d "$TMP_DIR/$APP_NAME" ]; then
  echo "Couldn't find $APP_NAME in the downloaded archive. Aborting."
  exit 1
fi

echo "==> Installing to $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
  echo "    (Replacing existing copy)"
  rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# If /Applications isn't writable (rare), fall back to the user's Applications folder.
if ! cp -R "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/" 2>/dev/null; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
  echo "    (No write access to /Applications — installing to $INSTALL_DIR instead)"
  cp -R "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/"
fi

echo "==> Removing macOS quarantine flag (so Gatekeeper won't nag you)..."
# -r recursive, -d delete the named attribute. The "|| true" is because the
# attribute may not actually be set on every nested file, which is fine.
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo ""
echo "Installed! Look for the trophy icon in your menu bar."
echo ""
echo "    Open it now:  open '$INSTALL_DIR/$APP_NAME'"
echo "    Source code:  https://github.com/${REPO}"
echo "    Star the repo if you like it!"
echo ""
