#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/build64/jk2mv"

if [[ ! -x "$RUNTIME_DIR/jk2mvmp" ]]; then
	echo "JK2MV has not been built. Run ./tools/jk2mv/build-macos-arm64.sh first." >&2
	exit 1
fi

cd "$RUNTIME_DIR"
exec ./jk2mvmp "$@"

