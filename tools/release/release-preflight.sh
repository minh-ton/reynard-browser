#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <--clean|--development>" >&2
	exit 2
fi

MODE="$1"
case "$MODE" in
	--clean) DIRTY=false ;;
	--development) DIRTY=true ;;
	*)
		echo "Usage: $0 <--clean|--development>" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

if [ "$DIRTY" = false ] && [ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)" ]; then
	echo "Release builds require a clean worktree, including staged and untracked files." >&2
	git -C "$ROOT_DIR" status --short >&2
	exit 1
fi

invalid_submodules="$(git -C "$ROOT_DIR" submodule status --recursive | sed -n '/^[+-U]/p')"
if [ -n "$invalid_submodules" ]; then
	echo "Submodule state does not match the recorded revisions:" >&2
	echo "$invalid_submodules" >&2
	exit 1
fi

"$ROOT_DIR/tools/firefox/prepare-firefox.sh" --check-prepared >/dev/null
toolchain_manifest="$($ROOT_DIR/tools/toolchains/validate-release-toolchain.sh)"

dirty_digest=clean
if [ "$DIRTY" = true ]; then
	dirty_digest="$({
		git -C "$ROOT_DIR" diff --binary HEAD
		git -C "$ROOT_DIR" ls-files --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do
			[ -f "$ROOT_DIR/$path" ] || continue
			printf 'untracked=%s|%s\n' "$path" "$(shasum -a 256 "$ROOT_DIR/$path" | awk '{print $1}')"
		done
	} | shasum -a 256 | awk '{print $1}')"
fi

printf 'dirty=%s\n' "$DIRTY"
printf 'dirty_digest=%s\n' "$dirty_digest"
printf '%s\n' "$toolchain_manifest"
printf 'parent_revision=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)"
git -C "$ROOT_DIR" submodule status --recursive | while IFS= read -r line; do
	set -- $line
	printf 'submodule_revision=%s|%s\n' "$2" "${1#[-+U ]}"
done
printf 'patch_manifest_sha256=%s\n' "$($ROOT_DIR/tools/firefox/prepare-firefox.sh --input-manifest | shasum -a 256 | awk '{print $1}')"
