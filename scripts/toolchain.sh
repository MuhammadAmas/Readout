#!/usr/bin/env bash

SWIFT_FLAGS=()

readout_configure_toolchain() {
    local developer plugins sdk interface arch
    developer="$(xcode-select -p 2>/dev/null || true)"
    [[ "$developer" == *CommandLineTools* ]] || return 0

    plugins="$developer/usr/lib/swift/host/plugins"
    if [[ -d "$plugins/testing" ]]; then
        SWIFT_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$plugins/testing")
    fi

    [[ -z "${SDKROOT:-}" && ! -e "$plugins/libSwiftUIMacros.dylib" ]] || return 0
    arch="$(uname -m)"
    [[ "$arch" == "arm64" ]] && arch="arm64e"
    for sdk in $(ls -d "$developer"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
        interface="$sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/$arch-apple-macos.swiftinterface"
        if [[ ! -f "$interface" ]] || ! grep -q 'public macro State()' "$interface"; then
            export SDKROOT="$sdk"
            echo "Readout: full Xcode not found, building against $(basename "$sdk")" >&2
            return 0
        fi
    done
    echo "Readout: no SDK on this Mac builds SwiftUI without Xcode. Install Xcode from the App Store." >&2
    return 1
}

readout_configure_toolchain
