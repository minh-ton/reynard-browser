#!/bin/sh

set -eu

if [ "${1:-}" != "--jailbroken-only" ] || [ "$#" -ne 1 ]; then
	echo "Usage: $0 --jailbroken-only" >&2
	exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"
BUILD_MODE_FILE="$ROOT_DIR/dist/build-mode"
SOURCE_MANIFEST="$ROOT_DIR/dist/source-revisions.txt"
FINAL_MANIFEST="$ROOT_DIR/dist/release-manifest.txt"

. "$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

cd "$ROOT_DIR"

"$ROOT_DIR/tools/release/release-preflight.sh" --clean >/dev/null

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


if [ ! -f "$SOURCE_MANIFEST" ] || ! grep -q '^dirty=false$' "$SOURCE_MANIFEST"; then
	echo "Archive source provenance is missing or was produced from dirty sources." >&2
	exit 1
fi
EXPECTED_ARCHIVE_HASH="$(sed -n 's/^archive_app_tree_sha256=//p' "$SOURCE_MANIFEST")"
ACTUAL_ARCHIVE_HASH="$("$ROOT_DIR/tools/release/hash-tree.sh" "$APP_PATH")"
if [ -z "$EXPECTED_ARCHIVE_HASH" ] || [ "$EXPECTED_ARCHIVE_HASH" != "$ACTUAL_ARCHIVE_HASH" ]; then
	echo "Archive contents changed after the release build." >&2
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

APP_BUNDLE="Payload/Reynard.app"
MAIN_EXECUTABLE="$APP_BUNDLE/Reynard"
HELPER_EXECUTABLE="$APP_BUNDLE/PlugIns/Reynard Helper.appex/Reynard Helper"
OPEN_IN_EXECUTABLE="$APP_BUNDLE/PlugIns/OpenIn.appex/OpenIn"
MACHO_LIST="$(mktemp "${TMPDIR:-/tmp}/reynard-macho-list.XXXXXX")"
trap 'rm -f "$MACHO_LIST"' EXIT HUP INT TERM

# Normalize only the packaging copy so the archived input remains immutable.
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_BUNDLE/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.Helper" "$APP_BUNDLE/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.OpenIn" "$APP_BUNDLE/PlugIns/OpenIn.appex/Info.plist"

if [ "$(plutil -extract CFBundleIdentifier raw "$APP_BUNDLE/Info.plist")" != "com.minh-ton.Reynard" ] ||
	[ "$(plutil -extract CFBundleIdentifier raw "$APP_BUNDLE/PlugIns/Reynard Helper.appex/Info.plist")" != "com.minh-ton.Reynard.Helper" ] ||
	[ "$(plutil -extract CFBundleIdentifier raw "$APP_BUNDLE/PlugIns/OpenIn.appex/Info.plist")" != "com.minh-ton.Reynard.OpenIn" ]; then
	echo "Bundle identifier preflight failed." >&2
	exit 1
fi

find "$APP_BUNDLE" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP_BUNDLE" -type f -name embedded.mobileprovision -delete

is_macho() {
	file -b "$1" | grep -q 'Mach-O'
}

find "$APP_BUNDLE" -type f -print | while IFS= read -r candidate; do
	if is_macho "$candidate"; then
		printf '%s\n' "$candidate"
	fi
done > "$MACHO_LIST"

SIGNED_BINARY_COUNT="$(wc -l < "$MACHO_LIST" | tr -d '[:space:]')"
if [ "$SIGNED_BINARY_COUNT" -eq 0 ]; then
	echo "No Mach-O binaries were found in the application bundle." >&2
	exit 1
fi

while IFS= read -r binary; do
	case "$binary" in
		"$MAIN_EXECUTABLE"|"$HELPER_EXECUTABLE"|"$OPEN_IN_EXECUTABLE"|"$PTRACE_JIT_OUT")
			continue
			;;
	esac
	ldid -S "$binary"
done < "$MACHO_LIST"

ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
ldid -S "$OPEN_IN_EXECUTABLE"
ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "$HELPER_EXECUTABLE"
ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "$MAIN_EXECUTABLE"

while IFS= read -r binary; do
	if ! ldid -e "$binary" >/dev/null 2>&1 || ! ldid -h "$binary" >/dev/null 2>&1; then
		echo "Jailbreak signature verification failed: ${binary#"$APP_BUNDLE/"}" >&2
		exit 1
	fi
done < "$MACHO_LIST"

echo "Verified jailbreak signatures for $SIGNED_BINARY_COUNT Mach-O binaries."
zip -qry ../Reynard-Jailbroken.ipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX"

IPA_PATH="$ROOT_DIR/dist/Reynard-Jailbroken.ipa"
unzip -tq "$IPA_PATH" >/dev/null
IPA_HASH="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
{
	cat "$SOURCE_MANIFEST"
	echo "packaged_app_tree_sha256=$("$ROOT_DIR/tools/release/hash-tree.sh" "$WORK_DIR/Payload/Reynard.app")"
	echo "signed_macho_count=$SIGNED_BINARY_COUNT"
	echo "ipa_sha256=$IPA_HASH"
} > "$FINAL_MANIFEST"
printf '%s  %s\n' "$IPA_HASH" "$(basename "$IPA_PATH")" > "$ROOT_DIR/dist/SHA256SUMS"
echo "Created and verified $IPA_PATH"
