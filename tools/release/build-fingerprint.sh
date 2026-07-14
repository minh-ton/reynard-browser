#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <gecko|idevice>" >&2
	exit 2
fi

COMPONENT="$1"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMP_INPUT="$(mktemp "${TMPDIR:-/tmp}/reynard-build-fingerprint.XXXXXX")"
trap 'rm -f "$TEMP_INPUT"' EXIT HUP INT TERM

hash_file() {
	path="$1"
	printf 'file=%s|%s\n' "${path#"$ROOT_DIR/"}" "$(shasum -a 256 "$path" | awk '{print $1}')"
}

{
	"$ROOT_DIR/tools/toolchains/validate-release-toolchain.sh"
	hash_file "$ROOT_DIR/tools/release/build-fingerprint.sh"
	hash_file "$ROOT_DIR/tools/toolchains/release.env"
	hash_file "$ROOT_DIR/tools/toolchains/validate-release-toolchain.sh"
	case "$COMPONENT" in
		gecko)
			MOZCONFIG="$ROOT_DIR/.build/firefox/.mozconfig"
			[ -f "$MOZCONFIG" ] || {
				echo "Missing Gecko configuration: $MOZCONFIG" >&2
				exit 1
			}
			printf 'component=gecko\n'
			if [ -n "${REYNARD_FIREFOX_INPUT_MANIFEST_SHA256:-}" ]; then
				firefox_input_hash="$REYNARD_FIREFOX_INPUT_MANIFEST_SHA256"
			else
				firefox_input_hash="$("$ROOT_DIR/tools/firefox/prepare-firefox.sh" --input-manifest | shasum -a 256 | awk '{print $1}')"
			fi
			printf 'firefox_input_manifest_sha256=%s\n' "$firefox_input_hash"
			hash_file "$MOZCONFIG"
			hash_file "$ROOT_DIR/tools/development/build-gecko.sh"
			hash_file "$ROOT_DIR/tools/firefox/gecko-artifact-manifest.sh"
			;;
		idevice)
			printf 'component=idevice\n'
			printf 'idevice_revision=%s\n' "$(git -C "$ROOT_DIR/support/idevice" rev-parse HEAD)"
			printf 'plist_ffi_revision=%s\n' "$(git -C "$ROOT_DIR/support/idevice/cpp/plist_ffi" rev-parse HEAD)"
			printf 'cargo_features=full,ring\n'
			printf 'cargo_profile=release\n'
			hash_file "$ROOT_DIR/tools/development/build-idevice.sh"
			;;
		*)
			echo "Usage: $0 <gecko|idevice>" >&2
			exit 2
			;;
	esac
} > "$TEMP_INPUT"

shasum -a 256 "$TEMP_INPUT" | awk '{print $1}'
