# Split-screen QA harness

This directory contains repeatable smoke and stress configs for local split-screen
multiplayer. The runner copies these configs into the active OpenJK homepath and
launches the native arm64 app with the game VMs disabled so the in-tree code is
tested.

## Run

```sh
tests/splitscreen/run_splitscreen_qa.sh
tests/splitscreen/run_external_gamepad_qa.sh
tests/splitscreen/run_external_menu_qa.sh
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

Controller simulation uses an external-process SDL bridge. OpenJK creates up to
four ordinary SDL virtual joysticks and listens only on localhost; the simulator
drives those devices from a separate process. Input then travels through the
same SDL polling, joystick-slot assignment, menu routing, bindings, and usercmd
generation as a physical controller. This avoids Apple's restricted virtual-HID
entitlement while still testing the actual controller path inside the engine.

Launch OpenJK with the bridge enabled, then build and drive it:

```sh
OPENJK_VIRTUAL_GAMEPADS=3 OPENJK_VIRTUAL_GAMEPAD_PORT=29180 openjk.arm64 ...
tests/splitscreen/build_external_input_sim.sh
tests/splitscreen/probe_external_gamepad_sim.sh
tests/splitscreen/external/macos_input_sim gamepad 1 axis 1 24000 wait 250 gamepad 1 axis 1 0
tests/splitscreen/external/macos_input_sim gamepad 2 button 0 tap
```

The older `hid-gamepad-demo` command remains available for machines with an
Apple-authorized `com.apple.developer.hid.virtual.device` signing identity, but
it is not required for automated QA.

The external menu run drives the stock player, saber, Force, top-menu, Controls,
join/spectate, virtual-keyboard, CVAR, cheat, and per-player console flows. The
controller shortcuts used by split-screen players are:

- Start: open that player's stock in-game top menu.
- Back + Start: toggle that player's Quake console.
- X: open that player's virtual keyboard from player setup.
- Left shoulder: open the stock saber setup screen.
- Right shoulder: open the stock Force setup screen.
- B or Back: cancel or return to the previous split-screen menu.
