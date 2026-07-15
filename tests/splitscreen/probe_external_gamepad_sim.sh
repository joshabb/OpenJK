#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/tests/splitscreen/external/macos_input_sim"

"$ROOT/tests/splitscreen/build_external_input_sim.sh" >/dev/null
"$ROOT/tests/splitscreen/sign_external_input_sim.sh" >/dev/null

set +e
"$BIN" gamepad-demo "${1:-1000}"
status=$?
set -e

if [[ $status -eq 0 ]]; then
	echo "external virtual HID gamepad probe passed"
	exit 0
fi

echo "external virtual HID gamepad probe failed with status $status" >&2
if [[ $status -eq 137 ]]; then
	echo "The process was killed by macOS after launch. With this tool, that usually means the restricted com.apple.developer.hid.virtual.device entitlement is embedded but not authorized by a real signing identity/provisioning profile." >&2
else
	echo "If the failure mentions com.apple.developer.hid.virtual.device, this Mac rejected the entitlement for this unsigned/local tool." >&2
fi
exit "$status"
