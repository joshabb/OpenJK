# Split-screen QA harness

This directory contains repeatable smoke and stress configs for local split-screen
multiplayer. The runner copies these configs into the active OpenJK homepath and
launches the native arm64 app with the game VMs disabled so the in-tree code is
tested.

## Run

```sh
tests/splitscreen/run_splitscreen_qa.sh
```

Useful overrides:

```sh
OPENJK_BIN=./build-arm64-native/openjk.arm64.app/Contents/MacOS/openjk.arm64 \
OPENJK_BASEPATH="/Users/joshabb/Library/Application Support/Steam/steamapps/common/Jedi Academy/SWJKJA.app/Contents" \
OPENJK_HOMEPATH=./runtime-home \
tests/splitscreen/run_splitscreen_qa.sh local_2p_ffa splitnet_localhost
```

Output is written under `runtime-home/base/qa-logs`, with screenshots and
condumps using names without spaces.

The default suite covers:

- 2, 3, and 4 player local split-screen FFA.
- 4 player team and CTF, plus duel.
- Death/respawn flow for split players.
- Per-player profile changes for name, model, saber, saber color, and force
  powers.
- Per-player join/spectate/rejoin state.
- Per-viewport stock player configuration, console, virtual keyboard, and
  control binding screens.
- Deterministic keyboard/mouse and controller routing with no input bleed.
- Controller button remapping, force powers, weapon selection, attack, alt
  attack, jump/use buttons, and a local combat command stream.
- Localhost split-network connection setup for players 2 through 4.

## External input simulator

The in-game QA configs are useful for deterministic assertions, but keyboard and
mouse can also be driven from outside OpenJK on macOS:

```sh
tests/splitscreen/build_external_input_sim.sh
tests/splitscreen/external/macos_input_sim request-permission
tests/splitscreen/external/macos_input_sim wait 1000 key w down wait 250 key w up mouse 40 0 click left
```

This uses Quartz/CGEvent and requires macOS Accessibility permission for the
terminal or parent process launching the simulator.

Controller simulation is different on macOS. There is no XInput API, and SDL
virtual joysticks are process-local. The external simulator includes a
`gamepad-demo <ms>` backend that attempts to create a real virtual HID gamepad
through `IOHIDUserDevice`, which is the correct macOS equivalent of an
outside-the-game controller. Apple requires the
`com.apple.developer.hid.virtual.device` entitlement for that backend; without
it, the tool fails explicitly instead of giving a false positive.

Build, sign, and probe the external gamepad backend:

```sh
tests/splitscreen/build_external_input_sim.sh
tests/splitscreen/sign_external_input_sim.sh
tests/splitscreen/probe_external_gamepad_sim.sh
```

`OPENJK_INPUT_SIM_SIGN_IDENTITY` can be set to a Developer ID or Apple
Development signing identity. The default is ad-hoc signing (`-`), which is
enough to embed the entitlement plist but may still be rejected by macOS because
the virtual HID entitlement is restricted.

If the probe exits `137` / `Killed: 9`, macOS killed the tool because the
restricted entitlement is present but not authorized by the signing identity.
Check available identities with:

```sh
security find-identity -v -p codesigning
```
