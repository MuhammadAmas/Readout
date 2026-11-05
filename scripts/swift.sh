#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
command="$1"
shift
exec swift "$command" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} "$@"
