#!/usr/bin/env bash
# Build signed, then install and launch on the paired iPhone (cable or Wi-Fi).
# Usage: scripts/install.sh [device-udid]
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UDID="${1:-}"
if [ -z "$UDID" ]; then
  UDID=$(xcrun devicectl list devices 2>/dev/null | grep -iE 'connected|available' \
    | grep -oiE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1 || true)
fi
if [ -z "$UDID" ]; then
  echo "No paired device found. Unlock the phone on the same Wi-Fi, or plug it in and trust this Mac." >&2
  exit 1
fi

scripts/build.sh --device
APP="$(pwd)/build/dd/Build/Products/Release-iphoneos/PogoLens.app"

# A wireless install often times out once while the tunnel comes up; the retry lands.
if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
  xcrun devicectl device info details --device "$UDID" >/dev/null 2>&1 || true
  xcrun devicectl device install app --device "$UDID" "$APP"
fi
xcrun devicectl device process launch --device "$UDID" --terminate-existing com.alexhedtke.pogolens
