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
	profile_customization_flow
	join_spectate_flow
	ui_console_keyboard
	controller_bind
	input_routing_sim
	gameplay_input_sim
	controls_force_combat_sim
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
cp "$ROOT/build-arm64-native/codemp/ui/uiarm64.dylib" "$HOMEPATH/base/"
cp "$ROOT/build-arm64-native/codemp/cgame/cgamearm64.dylib" "$HOMEPATH/base/"
cp "$ROOT/build-arm64-native/codemp/game/jampgamearm64.dylib" "$HOMEPATH/base/"

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
		+set net_port 29170 \
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
	if grep -Eq "SplitInputAssertModel: FAIL" "$log"; then
		echo "failed: $test_name emitted a split-input assertion failure"
		FAILURES=$((FAILURES + 1))
		continue
	fi
	if grep -Eq "SplitInputAssertCmd: FAIL" "$log"; then
		echo "failed: $test_name emitted a split-input command assertion failure"
		FAILURES=$((FAILURES + 1))
		continue
	fi
	if grep -Eq "SplitProfileAssert: FAIL" "$log"; then
		echo "failed: $test_name emitted a split-screen profile assertion failure"
		FAILURES=$((FAILURES + 1))
		continue
	fi
	if grep -Eq "SplitStateAssert: FAIL" "$log"; then
		echo "failed: $test_name emitted a split-screen state assertion failure"
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
		controller_bind)
			required_patterns=("Player 2 controller bind: \\+forward = JOY3" "cl_splitScreenP2Bind00 = .*3" "cl_splitScreenP2Bind01 = .*-1")
			;;
		input_routing_sim)
			required_patterns=("SplitInputRoute: keyboardOwner=1 controller1Owner=2" "SplitInputAssert after_controller" "SplitInputAssert after_keyboard" "SplitInputAssert after_mouse" "SplitInputSim: key device=controller1 player=2" "SplitInputSim: key device=keyboard player=1" "SplitInputSim: mouse device=mouse" "SplitInputAssertModel: PASS player=1" "SplitInputAssertModel: PASS player=2")
			;;
		gameplay_input_sim)
			required_patterns=("SplitStatus: p2 .*connected=1 team=FREE spectator=0" "SplitStatus: p3 .*connected=1 team=FREE spectator=0" "SplitStatus: p4 .*connected=1 team=FREE spectator=0" "SplitGameplayAssert keyboard_forward" "SplitGameplayAssert controller1_forward" "SplitGameplayAssert controller2_strafe" "SplitGameplayAssert controller3_altattack" "SplitGameplayAssert mouse_no_controller_bleed" "SplitInputSim: axis device=controller1 player=2 axis=1 value=127" "SplitInputSim: axis device=controller2 player=3 axis=0 value=-80" "SplitInputSim: button device=controller3 player=4 button=1 pressed=1" "SplitInputAssertCmd: PASS player=4")
			;;
		profile_customization_flow)
			required_patterns=("SplitProfileAssert: PASS player=2 key=name expected=QA_Profile2B" "SplitProfileAssert: PASS player=3 key=model expected=reborn/default" "SplitProfileAssert: PASS player=4 key=saber1 expected=desann" "SplitProfileAssert: PASS player=4 key=forcepowers expected=7-1-333003000313003120")
			;;
		join_spectate_flow)
			required_patterns=("SplitStateAssert: PASS player=2 expectedTeam=FREE actualTeam=FREE expectedSpectator=0 actualSpectator=0" "SplitStateAssert: PASS player=3 expectedTeam=SPECTATOR actualTeam=SPECTATOR expectedSpectator=1 actualSpectator=1" "SplitStateAssert: PASS player=4 expectedTeam=FREE actualTeam=FREE expectedSpectator=0 actualSpectator=0")
			;;
		controls_force_combat_sim)
			required_patterns=("SplitControlsAssert default_controls" "SplitControlsAssert custom_force_bindings" "SplitInputAssertCmd: PASS player=2 .*expectedButtons=512 .*expectedForce=3" "SplitInputAssertCmd: PASS player=3 .*expectedButtons=1024" "SplitInputAssertCmd: PASS player=4 .*expectedButtons=64" "SplitCombatAssert command_stream" "SplitStatus: p2 .*connected=1 team=FREE spectator=0" "SplitStatus: p3 .*connected=1 team=FREE spectator=0" "SplitStatus: p4 .*connected=1 team=FREE spectator=0")
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
