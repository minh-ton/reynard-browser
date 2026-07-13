#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/.build/firefox"

. "$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"

TARGET="aarch64-apple-ios"
LLVM_PREFIX="${LLVM_PREFIX:-/opt/homebrew/opt/llvm}"
WASM_CC="${WASM_CC:-$LLVM_PREFIX/bin/clang}"
WASM_CXX="${WASM_CXX:-$LLVM_PREFIX/bin/clang++}"

if [ ! -x "$WASM_CC" ] || [ ! -x "$WASM_CXX" ]; then
	echo "Missing WebAssembly compiler under $LLVM_PREFIX."
	echo "Install Homebrew LLVM or set WASM_CC and WASM_CXX explicitly."
	exit 1
fi

export WASM_CC WASM_CXX

cd "$ROOT_DIR"

"$ROOT_DIR/tools/firefox/prepare-firefox.sh"

rm -f "$FIREFOX_DIR/.mozconfig"

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
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
./mach build

GECKO_DIST="$FIREFOX_DIR/obj-aarch64-apple-ios/dist"
"$ROOT_DIR/tools/firefox/gecko-artifact-manifest.sh" write "$GECKO_DIST"
