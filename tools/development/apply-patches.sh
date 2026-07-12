#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
SUBMODULE_PATH="engine/firefox"
PATCH_DIR="${ROOT_DIR}/patches"

cd "$ROOT_DIR"

if [[ ! -f "engine/release.txt" ]]; then
	echo "Cannot get Firefox release tag: Missing engine/release.txt."
	exit 1
fi

RELEASE_TAG="$(tr -d '\000\r' < "engine/release.txt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [[ -z "$RELEASE_TAG" ]]; then
	echo "Cannot get Firefox release tag: engine/release.txt is empty."
	exit 1
fi

if ! git submodule status -- "$SUBMODULE_PATH" >/dev/null 2>&1; then
	echo "Missing submodule $SUBMODULE_PATH. Add it first, then run tools/development/update-gecko.sh."
	exit 1
fi

if ! git -C "$SUBMODULE_PATH" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null 2>&1; then
	echo "Tag $RELEASE_TAG does not exist in $SUBMODULE_PATH."
	echo "Run tools/development/update-gecko.sh to fetch and checkout the release tag."
	exit 1
fi

RELEASE_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse "$RELEASE_TAG^{commit}")"
HEAD_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"

if [[ "$HEAD_COMMIT" != "$RELEASE_COMMIT" ]]; then
	CURRENT_TAG="$(git -C "$SUBMODULE_PATH" describe --tags --exact-match HEAD 2>/dev/null || echo "no-exact-tag")"
	echo "Submodule HEAD ($HEAD_COMMIT, tag: $CURRENT_TAG) does not match engine/release.txt ($RELEASE_TAG -> $RELEASE_COMMIT)."
	echo "Run tools/development/update-gecko.sh to sync the submodule commit before applying patches."
	exit 1
fi

if [[ ! -d "$PATCH_DIR" ]]; then
	echo "Missing patches directory: $PATCH_DIR."
	exit 1
fi

if [[ -n "$(git -C "$SUBMODULE_PATH" status --porcelain)" ]]; then
	echo "$SUBMODULE_PATH has uncommitted changes. Commit, stash, or reset before applying patches."
	exit 1
fi

setopt null_glob
patch_files=()
for patch_file in "$PATCH_DIR"/**/*.patch; do
	if [[ "$patch_file" == "$PATCH_DIR/firefox/"* ]]; then
		continue
	fi
	patch_files+=("$patch_file")
done

if (( ${#patch_files[@]} == 0 )); then
	echo "No patch files found in $PATCH_DIR."
	exit 0
fi

echo "Applying patches to $SUBMODULE_PATH..."
for patch_file in $patch_files; do
	rel_path="${patch_file#$PATCH_DIR/}"
	echo "Applying $rel_path..."

	if ! git -C "$SUBMODULE_PATH" apply --3way --whitespace=nowarn "$patch_file"; then
		echo "Failed to apply $rel_path."
		echo "Resolve conflicts in $SUBMODULE_PATH, then press Enter to continue or type q to stop."
		read -r response
		if [[ "$response" == "q" || "$response" == "Q" ]]; then
			exit 1
		fi
	fi
done

echo "Finished applying patches."
