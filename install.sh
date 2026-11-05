#!/usr/bin/env bash
set -euo pipefail

repo="MuhammadAmas/Readout"
neural_voice=false

usage() {
    cat <<EOF
Installs Readout, a menu bar app that reads selected text aloud.

  curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | bash -s -- --with-neural-voice

Options:
  --with-neural-voice   also download the Kokoro neural voices (about 360 MB)
  -h, --help            show this help
EOF
}

fail() {
    echo "Readout: $*" >&2
    exit 1
}

for argument in "$@"; do
    case "$argument" in
        --with-neural-voice) neural_voice=true ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; fail "unknown option $argument" ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "Readout runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "Readout needs macOS 14 or later; this Mac has $(sw_vers -productVersion)."
if [[ "$(uname -m)" != "arm64" ]]; then
    fail "the prebuilt app is for Apple silicon. On an Intel Mac, build it from source:
  git clone https://github.com/$repo.git && cd Readout && make install"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
release="${READOUT_RELEASE_URL:-https://github.com/$repo/releases/latest/download}"

echo "Downloading Readout"
curl --fail --location --silent --show-error --retry 2 --output "$work/Readout.zip" "$release/Readout.zip"
curl --fail --location --silent --show-error --retry 2 --output "$work/Readout.zip.sha256" "$release/Readout.zip.sha256"
expected="$(awk '{print $1}' "$work/Readout.zip.sha256")"
actual="$(shasum -a 256 "$work/Readout.zip" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || fail "the download is corrupt (checksum mismatch). Try again."

ditto -x -k "$work/Readout.zip" "$work/unpacked"
[[ -d "$work/unpacked/Readout.app" ]] || fail "the download doesn't contain Readout.app."

applications="/Applications"
if [[ ! -w "$applications" ]]; then
    applications="$HOME/Applications"
    mkdir -p "$applications"
fi

if pgrep -x Readout >/dev/null; then
    osascript -e 'tell application id "dev.readout.Readout" to quit' >/dev/null 2>&1 || pkill -x Readout || true
    sleep 1
fi
rm -rf "$applications/Readout.app"
ditto "$work/unpacked/Readout.app" "$applications/Readout.app"
echo "Installed $applications/Readout.app"

if [[ "$neural_voice" == true ]]; then
    bash "$applications/Readout.app/Contents/Resources/fetch-neural-voice.sh"
fi

open "$applications/Readout.app"
cat <<EOF

Readout is running in the menu bar.
  1. In the welcome window, click Open Accessibility Settings and turn Readout on.
  2. Select text in any app and press Control-Option-R.
EOF
if [[ "$neural_voice" != true ]]; then
    echo "  For natural neural voices, run this command again with --with-neural-voice."
fi
