#!/usr/bin/env bash
# One-shot demo launcher: builds the OCaml runtime object for the chosen
# app, then the Qt binary via CMake, then runs it (under xvfb when no
# display is present). Usage: run.sh [todos|gallery]
set -euo pipefail

APP="${1:-todos}"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
QT_ROOT="$(cd "$DEMO_DIR/.." && pwd)"
BUILD_DIR="$QT_ROOT/build"

"$DEMO_DIR/build-runtime.sh" "$APP"

cmake -S "$QT_ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLUI_RUNTIME_OBJ="$DEMO_DIR/lui_${APP}_runtime.o"
cmake --build "$BUILD_DIR" --target lui_qt_todos -j"$(nproc)"

BIN="$(find "$BUILD_DIR" -name lui_qt_todos -type f | head -1)"
if [ -z "$BIN" ]; then
    echo "demo binary not found" >&2
    exit 1
fi

if [ -z "${DISPLAY:-}" ]; then
    exec xvfb-run -a "$BIN"
else
    exec "$BIN"
fi
