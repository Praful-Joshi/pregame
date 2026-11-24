#!/bin/zsh
# Build Pregame.app (release) and optionally install it into /Applications.
#   scripts/build-app.sh            -> build/Pregame.app
#   scripts/build-app.sh --install  -> also copy to /Applications
set -euo pipefail
cd "${0:A:h:h}"

# Every build is signed with the same self-signed identity and the hardened
# runtime, so macOS sees one app across rebuilds and keeps the folder access it
# was granted (docs/signing.md). Check for it before spending minutes building.
IDENTITY="${PREGAME_SIGNING_IDENTITY:-Pregame Self-Signed}"
# Lines read `1) <SHA-1> "name"`; a trusted identity is listed twice, so count hashes.
MATCHES="$(security find-identity -p codesigning | grep -F "\"$IDENTITY\"" | awk '{print $2}' | sort -u | grep -c . || true)"
if [[ "$MATCHES" == 0 ]]; then
  echo "error: no code-signing identity \"$IDENTITY\" in your keychains." >&2
  echo "Create it once with scripts/make-signing-identity.sh, or restore your backup; see docs/signing.md." >&2
  exit 1
elif [[ "$MATCHES" != 1 ]]; then
  echo "error: $MATCHES code-signing identities are named \"$IDENTITY\"; keep only the one in your backup (docs/signing.md)." >&2
  exit 1
fi

swift build -c release --product Pregame
BIN="$(swift build -c release --show-bin-path)"
APP="build/Pregame.app"
# TagLib from Homebrew, or from PREGAME_TAGLIB_PREFIX (as Package.swift reads it):
# releases build it for the minimum macOS with scripts/build-taglib.sh.
TAGLIB_PREFIX="${PREGAME_TAGLIB_PREFIX:-/opt/homebrew/opt/taglib}"
TAGLIB="${TAGLIB_PREFIX:A}/lib/libtag.2.dylib"
TAGLIB_LINKED="$(otool -D "$TAGLIB" | tail -1)"   # the path the app was linked against

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Pregame" "$APP/Contents/MacOS/Pregame"
cp -R "$BIN/Pregame_PregameCore.bundle" "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # from scripts/icon/make-icon.swift
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp Vendor/onnxruntime/LICENSE "$APP/Contents/Resources/ONNXRUNTIME_LICENSE"
cp Sources/QMDSP/COPYING "$APP/Contents/Resources/QMDSP_COPYING"
cp .build/checkouts/Sparkle/LICENSE "$APP/Contents/Resources/SPARKLE_LICENSE"
cp .build/checkouts/sentry-cocoa/LICENSE.md "$APP/Contents/Resources/SENTRY_LICENSE"

# Bundle TagLib so the app doesn't depend on Homebrew at runtime.
cp "$TAGLIB" "$APP/Contents/Frameworks/libtag.2.dylib"
chmod u+w "$APP/Contents/Frameworks/libtag.2.dylib"
install_name_tool -id "@rpath/libtag.2.dylib" "$APP/Contents/Frameworks/libtag.2.dylib"
install_name_tool -change "$TAGLIB_LINKED" "@rpath/libtag.2.dylib" "$APP/Contents/MacOS/Pregame"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Pregame"

# Sparkle (updates, docs/updates.md), straight from the pinned package's
# xcframework: the build's own copy lands in a different folder depending on
# the build system. ditto keeps the
# framework's symlinks. Drop the rpath into the build folder, so even on this
# Mac the app loads the embedded copy and its XPC services.
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# Sentry (opt-in crash reports, docs/privacy.md): its macOS framework is dynamic.
SENTRY=".build/artifacts/sentry-cocoa/Sentry-WithoutUIKitOrAppKit/Sentry-WithoutUIKitOrAppKit.xcframework/macos-arm64_x86_64/SentryWithoutUIKit.framework"
ditto "$SENTRY" "$APP/Contents/Frameworks/SentryWithoutUIKit.framework"
for rpath in $(otool -l "$APP/Contents/MacOS/Pregame" | awk '/LC_RPATH/ {getline; getline; print $2}'); do
  if [[ "$rpath" == "$PWD/.build/"* ]]; then
    install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/Pregame"
  fi
done

# ONNX Runtime (stems) and the Demucs model (exported to ONNX, see README).
cp Vendor/onnxruntime/lib/libonnxruntime.1.dylib "$APP/Contents/Frameworks/libonnxruntime.1.dylib"
chmod u+w "$APP/Contents/Frameworks/libonnxruntime.1.dylib"
if [[ -f Models/htdemucs.onnx.data ]]; then
  mkdir -p "$APP/Contents/Resources/Models"
  cp Models/htdemucs.onnx Models/htdemucs.onnx.data "$APP/Contents/Resources/Models/"
else
  echo "warning: Models/htdemucs.onnx.data is missing, so this build can't separate stems (scripts/stems/README.md)." >&2
fi

# Sparkle lifts the quarantine flag from an update's files after checking its
# signature, and can't from a file it can't write (SwiftPM checks packages out
# read-only), so make everything user-writable before sealing it.
chmod -R u+w "$APP"

# Libraries first, then the app, whose signature seals everything inside it.
# Sparkle's helpers are signed inside out with the app's identity, so an update
# satisfies the installed app's designated requirement. The Downloader gets
# Sparkle's own entitlements for it (sandbox plus network), which its packaged
# copy doesn't carry.
SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp=none)
"${SIGN[@]}" "$APP/Contents/Frameworks/libonnxruntime.1.dylib"
"${SIGN[@]}" "$APP/Contents/Frameworks/libtag.2.dylib"
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$SPARKLE_B/XPCServices/Installer.xpc"
"${SIGN[@]}" --entitlements .build/checkouts/Sparkle/Downloader/Downloader.entitlements "$SPARKLE_B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE_B/Autoupdate"
"${SIGN[@]}" "$SPARKLE_B/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP/Contents/Frameworks/SentryWithoutUIKit.framework"
"${SIGN[@]}" --entitlements scripts/Pregame.entitlements "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
codesign --display --requirements - "$APP" 2>/dev/null   # same on every build: see docs/signing.md

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Pregame.app
  cp -R "$APP" /Applications/Pregame.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Pregame.app
  echo "Installed /Applications/Pregame.app"
fi
