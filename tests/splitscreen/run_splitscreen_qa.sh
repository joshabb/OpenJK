#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${OPENJK_BIN:-$ROOT/build-arm64-native/openjk.arm64.app/Contents/MacOS/openjk.arm64}"
BASEPATH="${OPENJK_BASEPATH:-/Users/joshabb/Library/Application Support/Steam/steamapps/common/Jedi Academy/SWJKJA.app/Contents}"
HOMEPATH="${OPENJK_HOMEPATH:-$ROOT/runtime-home}"
CFG_SRC="$ROOT/tests/splitscreen/cfg"
CFG_DST="$HOMEPATH/base/splitqa"
LOG_DIR="$HOMEPATH/base/qa-logs"

DEFAULT_TESTS=(
	local_2p_ffa
	local_3p_ffa
	local_4p_ffa
	local_4p_team
	local_4p_ctf
	local_duel
	respawn_flow
	profile_cvars
	ui_console_keyboard
	splitnet_localhost
)

if [[ $# -gt 0 ]]; then
	TESTS=("$@")
else
	TESTS=("${DEFAULT_TESTS[@]}")
fi

if [[ ! -x "$BIN" ]]; then
	echo "Missing OpenJK binary: $BIN" >&2
	exit 2
fi

mkdir -p "$CFG_DST" "$LOG_DIR" "$HOMEPATH/base/screenshots"
cp "$CFG_SRC"/*.cfg "$CFG_DST"/

FAILURES=0
for test_name in "${TESTS[@]}"; do
	cfg="$CFG_DST/$test_name.cfg"
	log="$LOG_DIR/$test_name.stdout.txt"

	if [[ ! -f "$cfg" ]]; then
		echo "missing cfg: $test_name" >&2
		FAILURES=$((FAILURES + 1))
		continue
	fi

	echo "==> $test_name"
	set +e
	"$BIN" \
		+set fs_basepath "$BASEPATH" \
		+set fs_homepath "$HOMEPATH" \
		+set vm_game 0 \
		+set vm_cgame 0 \
		+set vm_ui 0 \
		+set r_fullscreen 0 \
		+set in_joystick 1 \
		+set logfile 2 \
		+exec "splitqa/$test_name.cfg" \
		> "$log" 2>&1
	status=$?
	set -e

	if [[ $status -ne 0 ]]; then
		echo "failed: $test_name exited $status"
		FAILURES=$((FAILURES + 1))
		continue
	fi

	if grep -Eiq "segmentation|assertion|fatal|recursive error|z_malloc failed|hunk_alloc failed|ERROR:" "$log"; then
		echo "failed: $test_name emitted an error marker"
		FAILURES=$((FAILURES + 1))
		continue
	fi

	required_patterns=()
	case "$test_name" in
		local_2p_ffa)
			required_patterns=("SplitStatus: p2 .*connected=1 team=FREE spectator=0")
			;;
		local_3p_ffa)
			required_patterns=("SplitStatus: p2 .*connected=1 team=FREE spectator=0" "SplitStatus: p3 .*connected=1 team=FREE spectator=0")
			;;
		local_4p_ffa|respawn_flow|profile_cvars|ui_console_keyboard)
			required_patterns=("SplitStatus: p2 .*connected=1 team=FREE spectator=0" "SplitStatus: p3 .*connected=1 team=FREE spectator=0" "SplitStatus: p4 .*connected=1 team=FREE spectator=0")
			;;
		local_4p_team)
			required_patterns=("SplitStatus: p2 .*connected=1 team=BLUE spectator=0" "SplitStatus: p3 .*connected=1 team=RED spectator=0" "SplitStatus: p4 .*connected=1 team=BLUE spectator=0")
			;;
		local_4p_ctf)
			required_patterns=("SplitStatus: p2 .*connected=1 team=BLUE spectator=0" "SplitStatus: p3 .*connected=1 team=RED spectator=0" "SplitStatus: p4 .*connected=1 team=BLUE spectator=0")
			;;
		local_duel)
			required_patterns=("SplitStatus: p2 .*connected=1 team=FREE spectator=0")
			;;
		splitnet_localhost)
			required_patterns=("SplitNet P2: enabled=1 state=8" "SplitNet P3: enabled=1 state=8" "SplitNet P4: enabled=1 state=8")
			;;
	esac

	for pattern in "${required_patterns[@]}"; do
		if ! grep -Eq "$pattern" "$log"; then
			echo "failed: $test_name missing required log pattern: $pattern"
			FAILURES=$((FAILURES + 1))
			continue 2
		fi
	done

	echo "passed: $test_name"
done

echo "logs: $LOG_DIR"
if [[ $FAILURES -ne 0 ]]; then
	echo "$FAILURES split-screen QA test(s) failed" >&2
	exit 1
fi

echo "all split-screen QA tests passed"
