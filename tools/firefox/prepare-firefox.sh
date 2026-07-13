#!/bin/sh

set -eu

MODE="apply"
case "${1:-}" in
	"") ;;
	--check) MODE="check" ;;
	--manifest) MODE="manifest" ;;
	*)
		echo "Usage: $0 [--check|--manifest]" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
PATCH_DIR="$ROOT_DIR/patches"
RELEASE_FILE="$ROOT_DIR/engine/release.txt"

PATCH_LIST="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-patches.XXXXXX")"
TEMP_INDEX="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-index.XXXXXX")"
trap 'rm -f "$PATCH_LIST" "$TEMP_INDEX"' EXIT HUP INT TERM
rm -f "$TEMP_INDEX"

if [ ! -f "$RELEASE_FILE" ]; then
	echo "Missing Firefox release file: $RELEASE_FILE" >&2
	exit 1
fi

if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
	echo "Firefox submodule is unavailable. Run: git submodule update --init engine/firefox" >&2
	exit 1
fi

RELEASE_TAG="$(tr -d '\000\r' < "$RELEASE_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [ -z "$RELEASE_TAG" ]; then
	echo "Firefox release file is empty: $RELEASE_FILE" >&2
	exit 1
fi

if ! git -C "$FIREFOX_DIR" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null; then
	echo "Firefox release tag is unavailable: $RELEASE_TAG" >&2
	echo "Run tools/development/update-gecko.sh before preparing Firefox." >&2
	exit 1
fi

EXPECTED_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD:engine/firefox)"
RELEASE_REVISION="$(git -C "$FIREFOX_DIR" rev-parse "$RELEASE_TAG^{commit}")"
ACTUAL_REVISION="$(git -C "$FIREFOX_DIR" rev-parse HEAD)"
if [ "$EXPECTED_REVISION" != "$RELEASE_REVISION" ] || [ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]; then
	echo "Firefox revision mismatch." >&2
	echo "Release:  $RELEASE_REVISION ($RELEASE_TAG)" >&2
	echo "Gitlink:  $EXPECTED_REVISION" >&2
	echo "Checkout: $ACTUAL_REVISION" >&2
	exit 1
fi

find "$PATCH_DIR" -type f -name '*.patch' ! -path "$PATCH_DIR/firefox/*" -print \
	| LC_ALL=C sort > "$PATCH_LIST"
find "$PATCH_DIR/firefox" -maxdepth 1 -type f -name '*.patch' -print \
	| LC_ALL=C sort >> "$PATCH_LIST"

PATCH_COUNT="$(wc -l < "$PATCH_LIST" | tr -d '[:space:]')"
if [ "$PATCH_COUNT" -eq 0 ]; then
	echo "No Firefox patches were found under $PATCH_DIR" >&2
	exit 1
fi

GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_DIR" read-tree HEAD
while IFS= read -r patch; do
	if ! GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_DIR" apply \
		--cached --3way --whitespace=nowarn "$patch" >/dev/null 2>&1; then
		echo "Firefox patch cannot be applied in series: ${patch#"$ROOT_DIR/"}" >&2
		exit 1
	fi
done < "$PATCH_LIST"

EXPECTED_TREE="$(GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_DIR" write-tree)"

source_matches_expected_tree() {
	GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_DIR" diff --quiet --
}

write_manifest() {
	printf 'manifest_version=1\n'
	printf 'firefox_release=%s\n' "$RELEASE_TAG"
	printf 'firefox_revision=%s\n' "$EXPECTED_REVISION"
	printf 'patched_tree=%s\n' "$EXPECTED_TREE"
	printf 'patch_count=%s\n' "$PATCH_COUNT"
	while IFS= read -r patch; do
		relative_path="${patch#"$ROOT_DIR/"}"
		patch_hash="$(shasum -a 256 "$patch" | awk '{print $1}')"
		printf 'patch=%s|%s\n' "$relative_path" "$patch_hash"
	done < "$PATCH_LIST"
}

if [ "$MODE" = "manifest" ]; then
	if ! source_matches_expected_tree; then
		echo "Firefox source does not match the complete expected patch series." >&2
		exit 1
	fi
	write_manifest
	exit 0
fi

if source_matches_expected_tree; then
	echo "Firefox source matches the complete $PATCH_COUNT-patch series."
	exit 0
fi

if [ "$MODE" = "check" ]; then
	echo "Firefox source does not match the complete expected patch series." >&2
	echo "Run tools/firefox/prepare-firefox.sh from a clean Firefox checkout." >&2
	exit 1
fi

if ! git -C "$FIREFOX_DIR" diff --quiet HEAD --; then
	echo "Firefox has partial or unrelated tracked changes; refusing to modify it." >&2
	exit 1
fi

echo "Applying $PATCH_COUNT Firefox patches in deterministic order..."
while IFS= read -r patch; do
	relative_path="${patch#"$ROOT_DIR/"}"
	echo "Applying $relative_path"
	git -C "$FIREFOX_DIR" apply --3way --whitespace=nowarn "$patch" >/dev/null
done < "$PATCH_LIST"

if ! source_matches_expected_tree; then
	echo "Firefox patch application completed but the resulting tree is unexpected." >&2
	exit 1
fi

echo "Firefox source preparation completed."
