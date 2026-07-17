#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <write|check> <gecko-dist>" >&2
	exit 2
fi

MODE="$1"
GECKO_DIST="$2"
case "$MODE" in
	write|check) ;;
	*)
		echo "Usage: $0 <write|check> <gecko-dist>" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$ROOT_DIR/tools/toolchains/release.env"
SOURCE_MANIFEST="$GECKO_DIST/reynard-source-manifest.txt"
ARTIFACT_MANIFEST="$GECKO_DIST/reynard-gecko-artifact-manifest.txt"
TEMP_SOURCE="$(mktemp "${TMPDIR:-/tmp}/reynard-gecko-source.XXXXXX")"
trap 'rm -f "$TEMP_SOURCE"' EXIT HUP INT TERM

if [ ! -f "$GECKO_DIST/bin/XUL" ]; then
	echo "Gecko XUL binary is unavailable under $GECKO_DIST/bin" >&2
	exit 1
fi

if [ "$MODE" = "check" ] && [ "${REYNARD_PREPARED_VERIFIED:-0}" != "1" ]; then
	"$SCRIPT_DIR/prepare-firefox.sh" --check-prepared >/dev/null
fi
PREPARED_DIR="$("$SCRIPT_DIR/prepare-firefox.sh" --print-dir)"
PREPARED_MARKER="$(git -C "$PREPARED_DIR" rev-parse --git-path reynard-prepared-manifest 2>/dev/null || true)"
if [ -n "$PREPARED_MARKER" ] && [ -f "$PREPARED_MARKER" ]; then
	{
		printf 'input_manifest_version=1\n'
		sed -n -e '/^firefox_release=/p' \
			-e '/^firefox_revision=/p' \
			-e '/^patch_count=/p' \
			-e '/^patch=/p' "$PREPARED_MARKER"
	} > "$TEMP_SOURCE"
else
	"$SCRIPT_DIR/prepare-firefox.sh" --input-manifest > "$TEMP_SOURCE"
fi
CURRENT_SOURCE_HASH="$(shasum -a 256 "$TEMP_SOURCE" | awk '{print $1}')"
BUILD_FINGERPRINT="$(REYNARD_FIREFOX_INPUT_MANIFEST_SHA256="$CURRENT_SOURCE_HASH" \
	"$SCRIPT_DIR/../release/build-fingerprint.sh" gecko)"

write_binary_hashes() {
	find "$GECKO_DIST/bin" -maxdepth 1 -type f \( -name 'XUL' -o -name '*.dylib' \) -print \
		| LC_ALL=C sort \
		| while IFS= read -r binary; do
			relative_path="${binary#"$GECKO_DIST/"}"
			hash="$(shasum -a 256 "$binary" | awk '{print $1}')"
			printf 'binary_sha256=%s|%s\n' "$relative_path" "$hash"
		done
}

if [ "$MODE" = "write" ]; then
	cp "$TEMP_SOURCE" "$SOURCE_MANIFEST"
	{
		printf 'manifest_version=2\n'
		printf 'build_fingerprint=%s\n' "$BUILD_FINGERPRINT"
		printf 'source_manifest_sha256=%s\n' "$(shasum -a 256 "$SOURCE_MANIFEST" | awk '{print $1}')"
		printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ';' | sed 's/;$//')"
		printf 'iphoneos_sdk=%s\n' "$(xcrun --sdk iphoneos --show-sdk-version)"
		printf 'rustc=%s\n' "$(rustup run "$REYNARD_RUST_TOOLCHAIN" rustc --version)"
		printf 'wasm_cc=%s\n' "${WASM_CC:-unset}"
		printf 'wasm_cxx=%s\n' "${WASM_CXX:-unset}"
		write_binary_hashes
	} > "$ARTIFACT_MANIFEST"
	echo "Wrote Gecko artifact manifest: $ARTIFACT_MANIFEST"
	exit 0
fi

if [ ! -f "$SOURCE_MANIFEST" ] || [ ! -f "$ARTIFACT_MANIFEST" ]; then
	echo "Gecko artifact provenance is missing under $GECKO_DIST" >&2
	exit 1
fi

EXPECTED_FINGERPRINT="$(sed -n 's/^build_fingerprint=//p' "$ARTIFACT_MANIFEST")"
if [ "$EXPECTED_FINGERPRINT" != "$BUILD_FINGERPRINT" ]; then
	echo "Gecko build fingerprint changed; rebuild Gecko artifacts." >&2
	exit 1
fi

if ! cmp -s "$TEMP_SOURCE" "$SOURCE_MANIFEST"; then
	echo "Gecko was built from a different Firefox source or patch series." >&2
	exit 1
fi

EXPECTED_SOURCE_HASH="$(sed -n 's/^source_manifest_sha256=//p' "$ARTIFACT_MANIFEST")"
ACTUAL_SOURCE_HASH="$(shasum -a 256 "$SOURCE_MANIFEST" | awk '{print $1}')"
if [ -z "$EXPECTED_SOURCE_HASH" ] || [ "$EXPECTED_SOURCE_HASH" != "$ACTUAL_SOURCE_HASH" ]; then
	echo "Gecko source manifest hash is invalid." >&2
	exit 1
fi

EXPECTED_XCODE="$(sed -n 's/^xcode=//p' "$ARTIFACT_MANIFEST")"
ACTUAL_XCODE="$(xcodebuild -version | tr '\n' ';' | sed 's/;$//')"
EXPECTED_SDK="$(sed -n 's/^iphoneos_sdk=//p' "$ARTIFACT_MANIFEST")"
ACTUAL_SDK="$(xcrun --sdk iphoneos --show-sdk-version)"
if [ "$EXPECTED_XCODE" != "$ACTUAL_XCODE" ] || [ "$EXPECTED_SDK" != "$ACTUAL_SDK" ]; then
	echo "Gecko was built with a different Xcode or iPhoneOS SDK." >&2
	echo "Built with: $EXPECTED_XCODE; iPhoneOS $EXPECTED_SDK" >&2
	echo "Selected:   $ACTUAL_XCODE; iPhoneOS $ACTUAL_SDK" >&2
	exit 1
fi

BINARY_COUNT=0
while IFS='|' read -r path hash; do
	case "$path" in
		binary_sha256=*) path="${path#binary_sha256=}" ;;
		*) continue ;;
	esac
	BINARY_COUNT=$((BINARY_COUNT + 1))
	binary="$GECKO_DIST/$path"
	if [ ! -f "$binary" ]; then
		echo "Gecko artifact is missing: $path" >&2
		exit 1
	fi
	actual_hash="$(shasum -a 256 "$binary" | awk '{print $1}')"
	if [ "$actual_hash" != "$hash" ]; then
		echo "Gecko artifact hash mismatch: $path" >&2
		exit 1
	fi
done < "$ARTIFACT_MANIFEST"

if [ "$BINARY_COUNT" -eq 0 ]; then
	echo "Gecko artifact manifest contains no binaries." >&2
	exit 1
fi

echo "Gecko source and $BINARY_COUNT binary artifacts match their manifest."
