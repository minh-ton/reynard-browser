#!/bin/sh

set -eu

MODE="prepare"
case "${1:-}" in
	"") ;;
	--check) MODE="check" ;;
	--check-prepared) MODE="check-prepared" ;;
	--manifest) MODE="manifest" ;;
	--print-dir) MODE="print-dir" ;;
	*)
		echo "Usage: $0 [--check|--check-prepared|--manifest|--print-dir]" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_REPOSITORY="$ROOT_DIR/engine/firefox"
PREPARED_DIR="$ROOT_DIR/.build/firefox"
PATCH_DIR="$ROOT_DIR/patches"
LOCAL_SERIES="$PATCH_DIR/firefox/series"
RELEASE_FILE="$ROOT_DIR/engine/release.txt"

PATCH_LIST="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-patches.XXXXXX")"
LOCAL_PATCH_LIST="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-local-patches.XXXXXX")"
DECLARED_LOCAL_LIST="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-declared-patches.XXXXXX")"
TEMP_INDEX="$(mktemp "${TMPDIR:-/tmp}/reynard-firefox-index.XXXXXX")"
trap 'rm -f "$PATCH_LIST" "$LOCAL_PATCH_LIST" "$DECLARED_LOCAL_LIST" "$TEMP_INDEX"' EXIT HUP INT TERM
rm -f "$TEMP_INDEX"

if [ "$MODE" = "print-dir" ]; then
	printf '%s\n' "$PREPARED_DIR"
	exit 0
fi

if [ ! -f "$RELEASE_FILE" ]; then
	echo "Missing Firefox release file: $RELEASE_FILE" >&2
	exit 1
fi
if [ ! -f "$LOCAL_SERIES" ]; then
	echo "Missing local Firefox patch series: $LOCAL_SERIES" >&2
	exit 1
fi
if [ ! -d "$FIREFOX_REPOSITORY/.git" ] && [ ! -f "$FIREFOX_REPOSITORY/.git" ]; then
	echo "Firefox submodule is unavailable. Run: git submodule update --init engine/firefox" >&2
	exit 1
fi

RELEASE_TAG="$(tr -d '\000\r' < "$RELEASE_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [ -z "$RELEASE_TAG" ]; then
	echo "Firefox release file is empty: $RELEASE_FILE" >&2
	exit 1
fi
if ! git -C "$FIREFOX_REPOSITORY" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null; then
	echo "Firefox release tag is unavailable: $RELEASE_TAG" >&2
	echo "Run tools/development/update-gecko.sh before preparing Firefox." >&2
	exit 1
fi

EXPECTED_REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD:engine/firefox)"
RELEASE_REVISION="$(git -C "$FIREFOX_REPOSITORY" rev-parse "$RELEASE_TAG^{commit}")"
ACTUAL_REVISION="$(git -C "$FIREFOX_REPOSITORY" rev-parse HEAD)"
if [ "$EXPECTED_REVISION" != "$RELEASE_REVISION" ] || [ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]; then
	echo "Firefox revision mismatch." >&2
	echo "Release:  $RELEASE_REVISION ($RELEASE_TAG)" >&2
	echo "Gitlink:  $EXPECTED_REVISION" >&2
	echo "Checkout: $ACTUAL_REVISION" >&2
	exit 1
fi
if ! git -C "$FIREFOX_REPOSITORY" diff --quiet HEAD -- ||
	! git -C "$FIREFOX_REPOSITORY" diff --cached --quiet HEAD --; then
	echo "The Firefox submodule must remain a clean source base." >&2
	exit 1
fi

find "$PATCH_DIR" -type f -name '*.patch' ! -path "$PATCH_DIR/firefox/*" -print \
	| LC_ALL=C sort > "$PATCH_LIST"
find "$PATCH_DIR/firefox" -maxdepth 1 -type f -name '*.patch' -print \
	| LC_ALL=C sort > "$LOCAL_PATCH_LIST"

while IFS= read -r entry || [ -n "$entry" ]; do
	case "$entry" in
		''|'#'*) continue ;;
		*/*|*'..'*)
			echo "Invalid local Firefox patch entry: $entry" >&2
			exit 1
			;;
	esac
	patch="$PATCH_DIR/firefox/$entry"
	if [ ! -f "$patch" ]; then
		echo "Declared local Firefox patch is missing: $entry" >&2
		exit 1
	fi
	printf '%s\n' "$patch" >> "$DECLARED_LOCAL_LIST"
done < "$LOCAL_SERIES"

if ! cmp -s "$LOCAL_PATCH_LIST" "$DECLARED_LOCAL_LIST"; then
	echo "Local Firefox patches do not exactly match patches/firefox/series." >&2
	diff -u "$DECLARED_LOCAL_LIST" "$LOCAL_PATCH_LIST" >&2 || true
	exit 1
fi
cat "$DECLARED_LOCAL_LIST" >> "$PATCH_LIST"

PATCH_COUNT="$(wc -l < "$PATCH_LIST" | tr -d '[:space:]')"
if [ "$PATCH_COUNT" -eq 0 ]; then
	echo "No Firefox patches were found under $PATCH_DIR" >&2
	exit 1
fi

GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_REPOSITORY" read-tree "$EXPECTED_REVISION"
PATCH_NUMBER=0
while IFS= read -r patch; do
	PATCH_NUMBER=$((PATCH_NUMBER + 1))
	if ! GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_REPOSITORY" apply \
		--cached --3way --whitespace=nowarn "$patch" >/dev/null 2>&1; then
		echo "Firefox patch $PATCH_NUMBER/$PATCH_COUNT cannot be applied: ${patch#"$ROOT_DIR/"}" >&2
		exit 1
	fi
done < "$PATCH_LIST"

EXPECTED_TREE="$(GIT_INDEX_FILE="$TEMP_INDEX" git -C "$FIREFOX_REPOSITORY" write-tree)"

write_manifest() {
	printf 'manifest_version=2\n'
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

prepared_source_matches() {
	[ -d "$PREPARED_DIR" ] &&
	[ "$(git -C "$PREPARED_DIR" rev-parse HEAD 2>/dev/null || true)" = "$EXPECTED_REVISION" ] &&
	[ "$(git -C "$PREPARED_DIR" write-tree 2>/dev/null || true)" = "$EXPECTED_TREE" ] &&
	git -C "$PREPARED_DIR" diff --quiet --
}

if [ "$MODE" = "manifest" ]; then
	write_manifest
	exit 0
fi
if [ "$MODE" = "check" ]; then
	echo "Firefox $PATCH_COUNT-patch series applies cleanly; expected tree $EXPECTED_TREE."
	exit 0
fi
if [ "$MODE" = "check-prepared" ]; then
	if ! prepared_source_matches; then
		echo "Prepared Firefox source does not match expected tree $EXPECTED_TREE." >&2
		exit 1
	fi
	echo "Prepared Firefox source matches expected tree $EXPECTED_TREE."
	exit 0
fi

SOURCE_COMMON_DIR="$(git -C "$FIREFOX_REPOSITORY" rev-parse --path-format=absolute --git-common-dir)"
if [ -e "$PREPARED_DIR" ]; then
	if ! git -C "$PREPARED_DIR" rev-parse --git-dir >/dev/null 2>&1; then
		echo "Refusing to replace non-worktree path: $PREPARED_DIR" >&2
		exit 1
	fi
	PREPARED_COMMON_DIR="$(git -C "$PREPARED_DIR" rev-parse --path-format=absolute --git-common-dir)"
	if [ "$PREPARED_COMMON_DIR" != "$SOURCE_COMMON_DIR" ]; then
		echo "Prepared Firefox path belongs to a different Git repository." >&2
		exit 1
	fi
else
	mkdir -p "$(dirname "$PREPARED_DIR")"
	git -C "$FIREFOX_REPOSITORY" worktree prune
	git -C "$FIREFOX_REPOSITORY" worktree add --detach "$PREPARED_DIR" "$EXPECTED_REVISION" >/dev/null
fi

if prepared_source_matches; then
	echo "Reusing prepared Firefox tree $EXPECTED_TREE at $PREPARED_DIR."
	exit 0
fi

git -C "$PREPARED_DIR" reset --hard "$EXPECTED_REVISION" >/dev/null
git -C "$PREPARED_DIR" clean -ffd >/dev/null
git -C "$PREPARED_DIR" read-tree --reset -u "$EXPECTED_TREE"

if ! prepared_source_matches; then
	echo "Prepared Firefox source does not match expected tree after checkout." >&2
	exit 1
fi

echo "Prepared Firefox $PATCH_COUNT-patch tree $EXPECTED_TREE at $PREPARED_DIR."
