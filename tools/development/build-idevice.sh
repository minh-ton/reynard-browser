#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SUBMODULE_PATH="$REPO_ROOT/support/idevice"
FFI_DIR="$SUBMODULE_PATH/ffi"
OUTPUT_LIB="$REPO_ROOT/browser/Reynard/JIT/RPPairing/libidevice_ffi.a"

TARGET_DIR="$SUBMODULE_PATH/target"
DEPLOYMENT_TARGET="13.0"

if [ ! -e "$SUBMODULE_PATH/.git" ]; then
  git -C "$REPO_ROOT" submodule update --init --recursive support/idevice
fi

RUST_TARGET="aarch64-apple-ios"
DEPLOYMENT_FLAG="-miphoneos-version-min=${DEPLOYMENT_TARGET}"
RUSTC_BIN="$(rustup which --toolchain stable rustc)"
CARGO_BIN="$(rustup which --toolchain stable cargo)"

if ! rustup target list --toolchain stable | grep -q "^$RUST_TARGET (installed)"; then
	rustup target add --toolchain stable "$RUST_TARGET"
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
cd "$FFI_DIR"
"$CARGO_BIN" build \
  --release \
  --target "$RUST_TARGET" \
  --no-default-features \
  --features full,ring
cp "$TARGET_DIR/$RUST_TARGET/release/libidevice_ffi.a" "$OUTPUT_LIB"
