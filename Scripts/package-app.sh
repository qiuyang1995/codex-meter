#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" == "debug" ]]; then
  SWIFT_CONFIG="debug"
else
  SWIFT_CONFIG="release"
fi

echo "==> Building CodexMeter ($SWIFT_CONFIG)"
swift build -c "$SWIFT_CONFIG" --product CodexMeter

BIN="$ROOT/.build/$SWIFT_CONFIG/CodexMeter"
if [[ ! -x "$BIN" ]]; then
  # Apple Silicon vs Intel triple folder
  BIN="$(find "$ROOT/.build" -type f -name CodexMeter -path "*/$SWIFT_CONFIG/*" | head -n 1)"
fi
if [[ -z "${BIN}" || ! -x "$BIN" ]]; then
  echo "error: built executable not found" >&2
  exit 1
fi

APP="$ROOT/CodexMeter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/CodexMeter"
cp "$ROOT/Sources/CodexMeter/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -d "$ROOT/Sources/CodexMeter/Resources/Assets.xcassets" ]] && command -v actool >/dev/null 2>&1; then
  if actool --compile "$APP/Contents/Resources" \
      --platform macosx \
      --minimum-deployment-target 13.0 \
      --app-icon AppIcon \
      --output-partial-info-plist /tmp/CodexMeter-asset-info.plist \
      "$ROOT/Sources/CodexMeter/Resources/Assets.xcassets" >/dev/null 2>&1; then
    echo "==> Compiled asset catalog"
  fi
fi

if [[ -f "$ROOT/Sources/CodexMeter/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Sources/CodexMeter/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP/Contents/MacOS/CodexMeter"
codesign --force --deep --sign - --entitlements "$ROOT/Sources/CodexMeter/Resources/CodexMeter.entitlements" "$APP" >/dev/null

echo "==> App ready: $APP"
echo "    open \"$APP\""
