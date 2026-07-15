#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/tests/splitscreen/external/macos_input_sim.c"
OUT="$ROOT/tests/splitscreen/external/macos_input_sim"

mkdir -p "$(dirname "$OUT")"
clang "$SRC" -o "$OUT" -framework ApplicationServices -framework CoreGraphics -framework IOKit
echo "$OUT"
