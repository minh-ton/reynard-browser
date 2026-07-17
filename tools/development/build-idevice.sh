#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REBUILD=false
case "${1:-}" in
  "") ;;
  --rebuild) REBUILD=true ;;
  *)
    echo "Usage: $0 [--rebuild]" >&2
    exit 2
    ;;
esac

source "$REPO_ROOT/tools/toolchains/release.env"

SUBMODULE_PATH="$REPO_ROOT/support/idevice"
FFI_DIR="$SUBMODULE_PATH/ffi"
OUTPUT_LIB="$REPO_ROOT/browser/Reynard/JIT/RPPairing/libidevice_ffi.a"
MANIFEST_DIR="$REPO_ROOT/.build/idevice"
ARTIFACT_MANIFEST="$MANIFEST_DIR/reynard-idevice-artifact-manifest.txt"

TARGET_DIR="$SUBMODULE_PATH/target"
DEPLOYMENT_TARGET="$REYNARD_DEPLOYMENT_TARGET"

if [ ! -e "$SUBMODULE_PATH/.git" ]; then
  git -C "$REPO_ROOT" submodule update --init --recursive support/idevice
fi

RUST_TARGET="$REYNARD_RUST_TARGET"
DEPLOYMENT_FLAG="-miphoneos-version-min=${DEPLOYMENT_TARGET}"
RUSTC_BIN="$(rustup which --toolchain "$REYNARD_RUST_TOOLCHAIN" rustc)"
CARGO_BIN="$(rustup which --toolchain "$REYNARD_RUST_TOOLCHAIN" cargo)"

"$REPO_ROOT/tools/toolchains/validate-release-toolchain.sh" >/dev/null

FINGERPRINT="$("$REPO_ROOT/tools/release/build-fingerprint.sh" idevice)"
if [[ "$REBUILD" == false && -f "$OUTPUT_LIB" && -f "$ARTIFACT_MANIFEST" ]]; then
  RECORDED_FINGERPRINT="$(sed -n 's/^fingerprint=//p' "$ARTIFACT_MANIFEST")"
  RECORDED_HASH="$(sed -n 's/^library_sha256=//p' "$ARTIFACT_MANIFEST")"
  ACTUAL_HASH="$(shasum -a 256 "$OUTPUT_LIB" | awk '{print $1}')"
  if [[ "$RECORDED_FINGERPRINT" == "$FINGERPRINT" && "$RECORDED_HASH" == "$ACTUAL_HASH" ]]; then
    echo "Reusing idevice library for fingerprint $FINGERPRINT."
    exit 0
  fi
fi

export IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
export RUSTC="$RUSTC_BIN"
if [ -n "${RUSTFLAGS:-}" ]; then
  export RUSTFLAGS="${RUSTFLAGS} -C link-arg=${DEPLOYMENT_FLAG}"
else
  export RUSTFLAGS="-C link-arg=${DEPLOYMENT_FLAG}"
fi
export TARGET_DIR

mkdir -p "$(dirname "$OUTPUT_LIB")"
mkdir -p "$MANIFEST_DIR"
if [[ "$REBUILD" == true ]]; then
  rm -rf "$TARGET_DIR/$RUST_TARGET/release"
fi
cd "$FFI_DIR"
"$CARGO_BIN" build \
  --release \
  --target "$RUST_TARGET" \
  --no-default-features \
  --features full,ring
cp "$TARGET_DIR/$RUST_TARGET/release/libidevice_ffi.a" "$OUTPUT_LIB"

{
  echo "manifest_version=1"
  echo "fingerprint=$FINGERPRINT"
  echo "library_sha256=$(shasum -a 256 "$OUTPUT_LIB" | awk '{print $1}')"
} > "$ARTIFACT_MANIFEST"
echo "Wrote idevice artifact manifest: $ARTIFACT_MANIFEST"
