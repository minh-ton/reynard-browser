#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"
MOZ_BUILD_JOBS="${MOZ_BUILD_JOBS:-12}"
CONFIGURED_MOZ_LINKER="${MOZ_LINKER:-}"
CONFIGURED_WASI_SYSROOT="${WASI_SYSROOT:-}"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

rm -f "$FIREFOX_DIR/.mozconfig"

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	if [ -n "$CONFIGURED_MOZ_LINKER" ]; then
		echo "ac_add_options --enable-linker=$CONFIGURED_MOZ_LINKER"
	fi
	if [ -n "$CONFIGURED_WASI_SYSROOT" ]; then
		echo "ac_add_options --with-wasi-sysroot=$CONFIGURED_WASI_SYSROOT"
	fi
	if [ -n "${SCCACHE_BIN:-}" ] && [ -x "$SCCACHE_BIN" ]; then
		echo "ac_add_options CCACHE=$SCCACHE_BIN"
	fi
	echo "ac_add_options --enable-ios-target=13.0"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
} > "$FIREFOX_DIR/.mozconfig"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
unset MOZ_LINKER

if [ -n "${SCCACHE_BIN:-}" ] && [ -x "$SCCACHE_BIN" ]; then
	"$SCCACHE_BIN" -s || true
fi

./mach build -j "$MOZ_BUILD_JOBS"

if [ -n "${SCCACHE_BIN:-}" ] && [ -x "$SCCACHE_BIN" ]; then
	"$SCCACHE_BIN" -s || true
fi
