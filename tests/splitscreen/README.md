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
