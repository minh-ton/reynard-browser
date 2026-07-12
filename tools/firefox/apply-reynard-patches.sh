#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
PATCH_DIR="$ROOT_DIR/patches/firefox"

if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
	echo "Firefox submodule is unavailable. Run: git submodule update --init engine/firefox" >&2
	exit 1
fi

expected_revision="$(git -C "$ROOT_DIR" rev-parse HEAD:engine/firefox)"
actual_revision="$(git -C "$FIREFOX_DIR" rev-parse HEAD)"
if [ "$actual_revision" != "$expected_revision" ]; then
	echo "Firefox revision mismatch." >&2
	echo "Expected: $expected_revision" >&2
	echo "Actual:   $actual_revision" >&2
	echo "Refresh the Reynard Firefox patches before building." >&2
	exit 1
fi

found_patch=0
for patch in "$PATCH_DIR"/*.patch; do
	if [ ! -f "$patch" ]; then
		continue
	fi
	found_patch=1
	name="$(basename "$patch")"
	if git -C "$FIREFOX_DIR" apply --reverse --check "$patch" >/dev/null 2>&1; then
		echo "Firefox patch already applied: $name"
	elif git -C "$FIREFOX_DIR" apply --check "$patch" >/dev/null 2>&1; then
		git -C "$FIREFOX_DIR" apply "$patch"
		echo "Applied Firefox patch: $name"
	else
		echo "Firefox patch is missing and cannot be applied cleanly: $name" >&2
		exit 1
	fi
done

if [ "$found_patch" -ne 1 ]; then
	echo "No Reynard Firefox patches were found in $PATCH_DIR" >&2
	exit 1
fi
