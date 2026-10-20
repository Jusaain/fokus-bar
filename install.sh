#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Fehler: FokusBar ist eine native macOS-App (macOS 14+ erforderlich)." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift / Xcode Command Line Tools fehlen. Bitte führe zuerst 'xcode-select --install' aus." >&2
  exit 1
fi

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "🔨 Baue und paketiere FokusBar.app (inkl. Natur-Sounds & Spotify-Playlists) …"
  make package
fi

APP_SRC="$ROOT_DIR/build/FokusBar.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Fehler: $APP_SRC wurde nicht gefunden." >&2
  exit 1
fi

# Wähle Zielordner: Wenn ~/Applications/FokusBar.app bereits existiert, aktualisiere dort,
# ansonsten installiere nach /Applications (falls beschreibbar) oder ~/Applications.
if [[ -n "${INSTALL_DIR:-}" ]]; then
  TARGET_DIR="$INSTALL_DIR"
elif [[ -d "$HOME/Applications/FokusBar.app" ]]; then
  TARGET_DIR="$HOME/Applications"
elif [[ -w "/Applications" ]]; then
  TARGET_DIR="/Applications"
else
  TARGET_DIR="$HOME/Applications"
fi

mkdir -p "$TARGET_DIR"
TARGET_APP="$TARGET_DIR/FokusBar.app"

pkill -x FokusBar 2>/dev/null || true
sleep 0.3

rm -rf "$TARGET_APP"
cp -R "$APP_SRC" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true
codesign --verify --deep --strict "$TARGET_APP"

echo "✅ FokusBar installiert unter: $TARGET_APP"
open "$TARGET_APP" --args --background
echo "🚀 FokusBar läuft jetzt oben in deiner macOS-Menüleiste."
