#!/bin/bash
# Build EasyAI.app on macOS (Apple Silicon / Intel).
set -euo pipefail

export http_proxy="${http_proxy:-http://127.0.0.1:10808}"
export https_proxy="${https_proxy:-http://127.0.0.1:10808}"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export PATH="${HOME}/Library/Python/3.9/bin:/opt/homebrew/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -e "src/api/api.h" ]; then
  echo "Run from lite-xl-easy source root"; exit 1
fi

BUILD_DIR="${BUILD_DIR:-build-easyai}"
APP_OUT="${APP_OUT:-$ROOT/dist/EasyAI.app}"

echo "==> meson setup"
rm -rf "$BUILD_DIR"
meson setup --buildtype=release -Dbundle=true --prefix=/ "$BUILD_DIR"

echo "==> meson compile"
meson compile -C "$BUILD_DIR"

echo "==> install bundle"
rm -rf "$APP_OUT"
mkdir -p "$(dirname "$APP_OUT")"
DESTDIR="$APP_OUT" meson install --skip-subprojects -C "$BUILD_DIR"

# Rename product branding inside bundle if stock name used
if [ -d "$ROOT/dist/Lite XL.app" ] && [ ! -d "$APP_OUT" ]; then
  mv "$ROOT/dist/Lite XL.app" "$APP_OUT"
fi

# Find whatever .app meson produced
if [ ! -d "$APP_OUT" ]; then
  found="$(find "$ROOT" -maxdepth 3 -name '*.app' -type d | head -1 || true)"
  if [ -n "$found" ]; then
    rm -rf "$APP_OUT"
    cp -R "$found" "$APP_OUT"
  fi
fi

if [ -d "$APP_OUT" ]; then
  APP_BIN_DIR="$APP_OUT/Contents/MacOS"
  PLIST="$APP_OUT/Contents/Info.plist"
  if [ -f "$APP_BIN_DIR/lite-xl" ] && [ ! -f "$APP_BIN_DIR/easyai" ]; then
    mv "$APP_BIN_DIR/lite-xl" "$APP_BIN_DIR/easyai"
  fi
  if [ -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable easyai" "$PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string easyai" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName EasyAI" "$PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleName string EasyAI" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName EasyAI" "$PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string EasyAI" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.easyai.editor" "$PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.easyai.editor" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleGetInfoString EasyAI" "$PLIST" 2>/dev/null || true
  fi
  echo "==> Built: $APP_OUT"
  ls -la "$APP_BIN_DIR"
  du -sh "$APP_OUT"
else
  echo "Bundle not found; look under $ROOT for build outputs"
  find "$ROOT" -maxdepth 3 -name '*.app' -type d
  exit 1
fi
