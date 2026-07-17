# Jedi Outcast multiplayer on Apple Silicon

OpenJK does not implement Jedi Outcast multiplayer. Its `codemp` targets are
for Jedi Academy. The maintained compatible engine for Outcast multiplayer is
[JK2MV](https://github.com/mvdevs/jk2mv).

`build-macos-arm64.sh` makes a reproducible native build from pinned JK2MV and
MVSDK revisions. It explicitly selects the arm64 processor and Homebrew prefix;
without both, JK2MV's current CMake setup can mis-detect an Intel build and add
the unsupported `-msse2` flag.

## Build

Install Xcode/CMake and native SDL2 (`brew install sdl2`), then run from the
OpenJK repository root:

```sh
./tools/jk2mv/build-macos-arm64.sh
```

The ignored output directory is `build64/jk2mv`.

## Run the client

The Steam Outcast data is normally under the path shown here:

```sh
./tools/jk2mv/run-macos-arm64.sh
```

JK2MV needs the original game's `base/assets0.pk3`, `assets1.pk3`,
`assets2.pk3`, and `assets5.pk3`. These proprietary files are not copied by the
build helper. The helper symlinks them from the normal Steam location. For a
different installation, set `JK2_GAME_DIR=/path/to/Jedi Knight II.app/Contents`
when building.

## Run a local dedicated server

```sh
cd build64/jk2mv
./jk2mvded +set dedicated 1 +map ffa_bespin
```
