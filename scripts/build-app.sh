#!/bin/bash
# Builds gaze-switch.app into ./build. Pass --install to also copy it to /Applications.
# It signs with SIGN_IDENTITY if set, else with the "gaze-switch local" certificate from
# make-signing-cert.sh if you've made one. Either keeps permissions across rebuilds. Without one
# the app is ad-hoc signed, and macOS asks for permissions again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

app=build/gaze-switch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/gaze-switch "$app/Contents/MacOS/gaze-switch"
cp Sources/gaze-switch/Info.plist "$app/Contents/Info.plist"
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-certificate -c "gaze-switch local" >/dev/null 2>&1; then
    identity="gaze-switch local"
fi
codesign --force --sign "${identity:--}" "$app"
echo "Built $app (signed with ${identity:-an ad-hoc signature})"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/gaze-switch.app
    cp -R "$app" /Applications/
    echo "Installed /Applications/gaze-switch.app"
fi
