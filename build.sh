#!/bin/bash
# Builds Badgeify.app. Works with Command Line Tools only (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${CONFIG:-release}
APP="build/Badgeify.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --disable-sandbox

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Badgeify" "$APP/Contents/MacOS/Badgeify"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Prefer a stable self-signed identity: TCC then binds the Accessibility grant to the
# certificate rather than to the binary's cdhash, so it survives rebuilds. Create one with
# ./scripts/create-signing-identity.sh — otherwise this falls back to an ad-hoc signature,
# where every rebuild voids the grant.
IDENTITY=${CODESIGN_IDENTITY:-Badgeify Local Signing}
if codesign --force --sign "$IDENTITY" --identifier com.local.badgeify "$APP" 2>/dev/null; then
  echo "==> signed with \"$IDENTITY\" (grant persists across rebuilds)"
  STABLE_SIGNATURE=1
else
  echo "==> signing (ad-hoc — run ./scripts/create-signing-identity.sh for a stable grant)"
  codesign --force --sign - --identifier com.local.badgeify "$APP"
  STABLE_SIGNATURE=0
fi

# With an ad-hoc signature the grant is cdhash-bound, so a rebuild silently voids it:
# System Settings keeps showing the toggle ON while the app is actually denied. Dropping
# the stale entry means a missing grant at least *looks* missing.
if [ "$STABLE_SIGNATURE" = "0" ] && [ "${SKIP_TCC_RESET:-0}" != "1" ]; then
  CDHASH=$(codesign -dvvv "$APP" 2>&1 | awk -F'=' '/^CDHash=/ {print $2}')
  STAMP="build/.cdhash"
  if [ "$CDHASH" != "$(cat "$STAMP" 2>/dev/null || true)" ]; then
    if [ -f "$STAMP" ]; then
      echo "==> code signature changed — clearing the now-void Accessibility grant"
      tccutil reset Accessibility com.local.badgeify >/dev/null 2>&1 || true
      echo "    re-grant it in Settings → General → Grant Access… after launching"
    fi
    echo "$CDHASH" > "$STAMP"
  fi
fi

echo "==> done: $(pwd)/$APP"
