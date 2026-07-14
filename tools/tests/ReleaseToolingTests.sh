#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reynard-release-tooling-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

TREE="$TEMP_DIR/tree"
mkdir -p "$TREE/nested"
printf 'one\n' > "$TREE/nested/file.txt"
FIRST_HASH="$("$ROOT_DIR/tools/release/hash-tree.sh" "$TREE")"
SECOND_HASH="$("$ROOT_DIR/tools/release/hash-tree.sh" "$TREE")"
[ "$FIRST_HASH" = "$SECOND_HASH" ] || {
	echo "Tree hashing is not deterministic." >&2
	exit 1
}

printf 'two\n' > "$TREE/nested/file.txt"
CHANGED_HASH="$("$ROOT_DIR/tools/release/hash-tree.sh" "$TREE")"
[ "$FIRST_HASH" != "$CHANGED_HASH" ] || {
	echo "Tree hashing did not detect changed content." >&2
	exit 1
}

DEVELOPMENT_ONE="$TEMP_DIR/development-one.txt"
DEVELOPMENT_TWO="$TEMP_DIR/development-two.txt"
"$ROOT_DIR/tools/release/release-preflight.sh" --development > "$DEVELOPMENT_ONE"
"$ROOT_DIR/tools/release/release-preflight.sh" --development > "$DEVELOPMENT_TWO"
FIRST_DIRTY_HASH="$(sed -n 's/^dirty_digest=//p' "$DEVELOPMENT_ONE")"
SECOND_DIRTY_HASH="$(sed -n 's/^dirty_digest=//p' "$DEVELOPMENT_TWO")"
[ -n "$FIRST_DIRTY_HASH" ] && [ "$FIRST_DIRTY_HASH" = "$SECOND_DIRTY_HASH" ] || {
	echo "Development source hashing is not deterministic." >&2
	exit 1
}

echo "Release tooling tests passed."
