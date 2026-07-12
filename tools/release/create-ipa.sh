#!/bin/sh

set -eu

if [ "${1:-}" != "--jailbroken-only" ] || [ "$#" -ne 1 ]; then
	echo "Usage: $0 --jailbroken-only" >&2
	exit 2
fi

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"
BUILD_MODE_FILE="$ROOT_DIR/dist/build-mode"

cd "$ROOT_DIR"

if [ ! -f "$BUILD_MODE_FILE" ] || [ "$(cat "$BUILD_MODE_FILE")" != "jailbroken" ]; then
	echo "The archive was not produced in jailbroken mode." >&2
	echo "Run tools/release/build-app.sh --jailbroken first." >&2
	exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
	echo "Missing required tool: ldid" >&2
	exit 1
fi

if [ ! -d "$APP_DIR" ]; then
	echo "Missing archive output at $APP_DIR"
	echo "Run tools/release/build-app.sh first."
	exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
	echo "No .app found in $APP_DIR"
	exit 1
fi

# Normalize identifiers before jailbreak signing because unsigned archives may
# not retain the distribution identifiers from the project configuration.
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_PATH/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.Helper" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.OpenIn" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"

if [ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")" != "com.minh-ton.Reynard" ] ||
	[ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist")" != "com.minh-ton.Reynard.Helper" ] ||
	[ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/PlugIns/OpenIn.appex/Info.plist")" != "com.minh-ton.Reynard.OpenIn" ]; then
	echo "Bundle identifier preflight failed." >&2
	exit 1
fi

rm -rf \
	"$WORK_DIR" \
	"$ROOT_DIR/dist/Reynard.ipa" \
	"$ROOT_DIR/dist/Reynard-TrollStore.tipa" \
	"$ROOT_DIR/dist/Reynard-Jailbroken.ipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"
PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

"$CLANG_PATH" \
	-arch arm64 \
	-isysroot "$SDK_PATH" \
	-miphoneos-version-min=13.0 \
	-Os \
	"$PTRACE_JIT_SRC" \
	-o "$PTRACE_JIT_OUT"

chmod 0755 "$PTRACE_JIT_OUT"
ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard"
ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper"
zip -r ../Reynard-Jailbroken.ipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
