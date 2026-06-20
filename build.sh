#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
GENERATOR="${GENERATOR:-Ninja}"

if [[ "${1:-}" == "clean" ]]; then
  cmake --build "$BUILD_DIR" --target clean 2>/dev/null || true
  rm -f libraries/web_lxl/init.so libraries/web_lxl/init.dylib libraries/web_lxl/init.lib
  exit 0
fi

cmake -S . -B "$BUILD_DIR" -G "$GENERATOR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  "$@"

cmake --build "$BUILD_DIR"
