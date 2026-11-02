#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache .build/clang-cache .build/spm-cache .build/config .build/security dist
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
# Rebuild the runtime assets from the source art when it is here; a checkout without Art/ and the
# historical project builds from the prepared Sources/Dafeiyu/Resources/Assets as committed.
if [ -d Art/gaze32/selected ] && [ -d ../01_历史项目 ]; then
  swift -module-cache-path "$ROOT/.build/module-cache" Scripts/prepare-gaze.swift "$ROOT"
  swift -module-cache-path "$ROOT/.build/module-cache" Scripts/prepare-assets.swift "$ROOT"
fi
SPM=(--build-system native -debug-info-format none --disable-sandbox --scratch-path "$ROOT/.build" --cache-path "$ROOT/.build/spm-cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" --manifest-cache local)
swift build -c release "${SPM[@]}" -Xswiftc -module-cache-path -Xswiftc "$ROOT/.build/module-cache"
BIN="$(swift build -c release "${SPM[@]}" --show-bin-path)"
STAGE="$(mktemp -d /private/tmp/dafeiyu-standalone.XXXXXX)"
APP="$STAGE/大肥鱼.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Dafeiyu" "$APP/Contents/MacOS/Dafeiyu"
ditto --noextattr --norsrc --noqtn "$BIN/Dafeiyu_Dafeiyu.bundle" "$APP/Contents/Resources/Dafeiyu_Dafeiyu.bundle"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
# This is our newly assembled bundle. Archive/source metadata stays untouched.
xattr -cr "$APP"
# Sign with the local "Dafeiyu Local Signing" identity from the login keychain when it exists: its
# designated requirement (bundle id + certificate) stays the same across builds, so macOS keeps the
# Accessibility permission after an update. Ad-hoc signing changes it with every build.
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk '/"Dafeiyu Local Signing"/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no \"Dafeiyu Local Signing\" identity; signing ad-hoc (Accessibility must be granted again after install)" >&2
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
# Name the package from Info.plist so a new build never overwrites an older fallback ZIP.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)"
ditto -c -k --norsrc --keepParent "$APP" "$ROOT/dist/大肥鱼-$VERSION.zip"
printf '%s\n' "$APP" > "$ROOT/dist/run-app-path.txt"
printf '%s\n' "$APP"
