#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

echo "apply-reynard-patches.sh is retained for compatibility; preparing the complete Firefox patch series."
exec "$SCRIPT_DIR/prepare-firefox.sh" "$@"
