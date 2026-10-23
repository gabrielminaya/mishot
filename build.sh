#!/bin/zsh
# Builds, signs and installs MiShot into /Applications.
set -e
cd "$(dirname "$0")"
APP=build/MiShot.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 Sources/*.swift -o $APP/Contents/MacOS/MiShot
cp Info.plist $APP/Contents/
[ -f AppIcon.icns ] && cp AppIcon.icns $APP/Contents/Resources/
# Sign with a stable identity so the Screen Recording permission survives rebuilds
# (ad-hoc signatures change every build and macOS would ask again).
codesign --force --options runtime --sign "${SIGN_ID:-A514F3CAAF91740B7C7762FBC849A929D5AA86FA}" $APP
pkill -x MiShot 2>/dev/null || true
rm -rf /Applications/MiShot.app && ditto $APP /Applications/MiShot.app
echo "Instalado en /Applications/MiShot.app"
