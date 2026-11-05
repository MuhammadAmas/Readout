#!/usr/bin/env bash
set -euo pipefail

runtime_version="v1.13.8"
runtime_archive="sherpa-onnx-${runtime_version}-osx-universal2-shared-lib.tar.bz2"
runtime_sha256="c1cca5b4a1867543e27d42fbea513983e73f629d0aa53b43b51555a71d2108d9"
runtime_url="https://github.com/k2-fsa/sherpa-onnx/releases/download/${runtime_version}/${runtime_archive}"

model_name="kokoro-multi-lang-v1_0"
model_archive="${model_name}.tar.bz2"
model_sha256="60703707bc05ccd48d60e1eb723f38b07d6e474795a0b6a588d7220400e0f7a4"
model_url="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${model_archive}"

destination="${READOUT_NEURAL_DIR:-$HOME/Library/Application Support/Readout/Neural}"
downloads="$(mktemp -d)"
trap 'rm -rf "$downloads"' EXIT

fetch() {
    local url="$1" archive="$2" expected="$3"
    echo "Downloading $archive"
    curl --fail --location --progress-bar --output "$downloads/$archive" "$url"
    local actual
    actual="$(shasum -a 256 "$downloads/$archive" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for $archive: expected $expected, got $actual" >&2
        exit 1
    fi
}

mkdir -p "$destination"

if [[ "$(cat "$destination/runtime/VERSION" 2>/dev/null)" == "$runtime_version" ]]; then
    echo "Runtime already installed"
else
    fetch "$runtime_url" "$runtime_archive" "$runtime_sha256"
    mkdir -p "$downloads/runtime"
    tar -xjf "$downloads/$runtime_archive" -C "$downloads/runtime" --strip-components 1
    rm -rf "$destination/runtime"
    mkdir -p "$destination/runtime"
    cp -R "$downloads/runtime/lib" "$destination/runtime/lib"
    echo "$runtime_version" > "$destination/runtime/VERSION"
fi

if [[ -f "$destination/$model_name/model.onnx" ]]; then
    echo "Model already installed"
else
    fetch "$model_url" "$model_archive" "$model_sha256"
    tar -xjf "$downloads/$model_archive" -C "$downloads"
    rm -rf "$destination/$model_name"
    mv "$downloads/$model_name" "$destination/$model_name"
fi

xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true
echo "Neural voice installed in $destination"
du -sh "$destination"
