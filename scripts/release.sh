#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
scripts/build-app.sh

mkdir -p dist
rm -f dist/Readout.zip dist/Readout.zip.sha256
ditto -c -k --norsrc --keepParent build/Readout.app dist/Readout.zip
(cd dist && shasum -a 256 Readout.zip > Readout.zip.sha256)

echo
echo "Readout $version packaged:"
ls -lh dist/Readout.zip | awk '{print "  dist/Readout.zip (" $5 ")"}'
echo "  dist/Readout.zip.sha256 ($(awk '{print $1}' dist/Readout.zip.sha256))"
echo
echo "Publish it with:"
echo "  gh release create v$version dist/Readout.zip dist/Readout.zip.sha256 --title \"Readout $version\" --generate-notes"
