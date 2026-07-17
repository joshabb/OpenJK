#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
	echo "This helper is for Apple Silicon macOS." >&2
	exit 1
fi

if [[ ! -f /opt/homebrew/lib/libSDL2.dylib ]]; then
	echo "Native SDL2 is required. Install it with: brew install sdl2" >&2
	exit 1
fi

JK2MV_COMMIT=7d601454c3db68492289d4d4e3dc30bff39e4246
MVSDK_COMMIT=4c7c463638192aead1ff3de8a88cc5de266bf3a2
OUTPUT_DIR="${1:-$PWD/build64/jk2mv}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jk2mv-arm64.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -L --fail --retry 3 \
	"https://github.com/mvdevs/jk2mv/archive/$JK2MV_COMMIT.tar.gz" \
	-o "$WORK_DIR/jk2mv.tar.gz"
curl -L --fail --retry 3 \
	"https://github.com/mvdevs/mvsdk/archive/$MVSDK_COMMIT.tar.gz" \
	-o "$WORK_DIR/mvsdk.tar.gz"

mkdir -p "$WORK_DIR/source" "$WORK_DIR/sdk"
tar -xzf "$WORK_DIR/jk2mv.tar.gz" -C "$WORK_DIR/source" --strip-components=1
tar -xzf "$WORK_DIR/mvsdk.tar.gz" -C "$WORK_DIR/sdk" --strip-components=1
cp -R "$WORK_DIR/sdk/." "$WORK_DIR/source/src/mvsdk/"

cmake -S "$WORK_DIR/source" -B "$WORK_DIR/build" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DSystemProcessor=arm64 \
	-DCMAKE_PREFIX_PATH=/opt/homebrew \
	-DBuildPortableVersion=ON
cmake --build "$WORK_DIR/build" --parallel "$(sysctl -n hw.logicalcpu)"

mkdir -p "$OUTPUT_DIR"
cp -R "$WORK_DIR/build/out/Release/." "$OUTPUT_DIR/"

DEFAULT_GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Jedi Outcast/Jedi Knight II.app/Contents"
GAME_DIR="${JK2_GAME_DIR:-$DEFAULT_GAME_DIR}"
if [[ -d "$GAME_DIR/base" ]]; then
	for asset in assets0.pk3 assets1.pk3 assets2.pk3 assets5.pk3; do
		if [[ -f "$GAME_DIR/base/$asset" ]]; then
			ln -sfn "$GAME_DIR/base/$asset" "$OUTPUT_DIR/base/$asset"
		fi
	done
	echo "Linked legally installed game data from: $GAME_DIR"
else
	echo "No Steam game data found. Set JK2_GAME_DIR and rerun, or link assets0/1/2/5.pk3 into $OUTPUT_DIR/base." >&2
fi
echo "Native JK2MV build written to: $OUTPUT_DIR"
