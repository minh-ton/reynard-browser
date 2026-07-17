#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

. "$ROOT_DIR/tools/toolchains/release.env"
. "$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"

fail_mismatch() {
	tool="$1"
	expected="$2"
	actual="$3"
	echo "$tool version mismatch." >&2
	echo "Expected: $expected" >&2
	echo "Actual:   $actual" >&2
	exit 1
}

actual_xcode_build="$(xcodebuild -version | sed -n '2s/^Build version //p')"
[ "$REYNARD_XCODE_BUILD" = "$actual_xcode_build" ] ||
	fail_mismatch "Xcode build" "$REYNARD_XCODE_BUILD" "$actual_xcode_build"

actual_sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
[ "$REYNARD_IPHONEOS_SDK_VERSION" = "$actual_sdk" ] ||
	fail_mismatch "iPhoneOS SDK" "$REYNARD_IPHONEOS_SDK_VERSION" "$actual_sdk"

if ! rustup toolchain list | grep -q "^$REYNARD_RUST_TOOLCHAIN-"; then
	echo "Missing pinned Rust toolchain: $REYNARD_RUST_TOOLCHAIN" >&2
	echo "Install it explicitly with: rustup toolchain install $REYNARD_RUST_TOOLCHAIN --profile minimal --target $REYNARD_RUST_TARGET" >&2
	exit 1
fi

actual_rustc="$(rustup run "$REYNARD_RUST_TOOLCHAIN" rustc --version)"
[ "$REYNARD_RUSTC_VERSION" = "$actual_rustc" ] ||
	fail_mismatch "rustc" "$REYNARD_RUSTC_VERSION" "$actual_rustc"
actual_cargo="$(rustup run "$REYNARD_RUST_TOOLCHAIN" cargo --version)"
[ "$REYNARD_CARGO_VERSION" = "$actual_cargo" ] ||
	fail_mismatch "cargo" "$REYNARD_CARGO_VERSION" "$actual_cargo"

if ! rustup target list --toolchain "$REYNARD_RUST_TOOLCHAIN" | grep -q "^$REYNARD_RUST_TARGET (installed)"; then
	echo "Missing Rust target $REYNARD_RUST_TARGET for $REYNARD_RUST_TOOLCHAIN." >&2
	exit 1
fi

llvm_prefix="${LLVM_PREFIX:-/opt/homebrew/opt/llvm}"
llvm_line="$($llvm_prefix/bin/clang --version | sed -n '1p')"
case "$llvm_line" in
	*"clang version $REYNARD_LLVM_VERSION"*) ;;
	*) fail_mismatch "LLVM" "$REYNARD_LLVM_VERSION" "$llvm_line" ;;
esac

if command -v ldid >/dev/null 2>&1; then
	if ! command -v brew >/dev/null 2>&1; then
		echo "Homebrew is required to verify the pinned ldid version." >&2
		exit 1
	fi
	actual_ldid="$(brew list --versions ldid 2>/dev/null | awk 'NR == 1 { print $2 }')"
	[ "$REYNARD_LDID_VERSION" = "$actual_ldid" ] ||
		fail_mismatch "ldid" "$REYNARD_LDID_VERSION" "${actual_ldid:-unavailable}"
fi

printf 'xcode_version=%s\n' "$REYNARD_XCODE_VERSION"
printf 'xcode_build=%s\n' "$REYNARD_XCODE_BUILD"
printf 'iphoneos_sdk_version=%s\n' "$REYNARD_IPHONEOS_SDK_VERSION"
printf 'rust_toolchain=%s\n' "$REYNARD_RUST_TOOLCHAIN"
printf 'rustc_version=%s\n' "$REYNARD_RUSTC_VERSION"
printf 'cargo_version=%s\n' "$REYNARD_CARGO_VERSION"
printf 'rust_target=%s\n' "$REYNARD_RUST_TARGET"
printf 'llvm_version=%s\n' "$REYNARD_LLVM_VERSION"
printf 'deployment_target=%s\n' "$REYNARD_DEPLOYMENT_TARGET"
printf 'ldid_version=%s\n' "$REYNARD_LDID_VERSION"
