#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh

configuration="${CONFIGURATION:-release}"
local_identity="Readout Local Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    identity="$SIGN_IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -q "\"$local_identity\""; then
    identity="$local_identity"
else
    identity="-"
fi
app="build/Readout.app"

swift build -c "$configuration" --product Readout ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
binaries="$(swift build -c "$configuration" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binaries/Readout" "$app/Contents/MacOS/Readout"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp scripts/fetch-neural-voice.sh "$app/Contents/Resources/fetch-neural-voice.sh"
codesign --force --sign "$identity" --identifier dev.readout.Readout "$app"
if [[ "$identity" == "-" ]]; then
    echo "Built $app (ad-hoc signed: Accessibility access resets on every rebuild; run scripts/create-signing-identity.sh to fix)"
else
    echo "Built $app (signed with \"$identity\")"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Readout 2>/dev/null || true
    rm -rf /Applications/Readout.app
    cp -R "$app" /Applications/Readout.app
    echo "Installed /Applications/Readout.app"
fi
