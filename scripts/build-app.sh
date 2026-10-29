#!/bin/bash
# Builds gaze-switch.app into ./build. Pass --install to also copy it to /Applications.
# Set SIGN_IDENTITY to a code-signing certificate's name to keep permissions across rebuilds;
# without one the app is ad-hoc signed and macOS asks for permissions again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

app=build/gaze-switch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/gaze-switch "$app/Contents/MacOS/gaze-switch"
cp Sources/gaze-switch/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/gaze-switch.app
    cp -R "$app" /Applications/
    echo "Installed /Applications/gaze-switch.app"
fi
