#!/bin/sh

set -eu

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
	echo "Usage: $0 <directory>" >&2
	exit 2
fi

ROOT="$1"
TEMP_HASHES="$(mktemp "${TMPDIR:-/tmp}/reynard-tree-hashes.XXXXXX")"
trap 'rm -f "$TEMP_HASHES"' EXIT HUP INT TERM

find "$ROOT" \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r path; do
	relative_path="${path#"$ROOT/"}"
	if [ -L "$path" ]; then
		printf 'symlink=%s|%s\n' "$relative_path" "$(readlink "$path")"
	else
		printf 'file=%s|%s\n' "$relative_path" "$(shasum -a 256 "$path" | awk '{print $1}')"
	fi
done > "$TEMP_HASHES"

shasum -a 256 "$TEMP_HASHES" | awk '{print $1}'
