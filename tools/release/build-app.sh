#!/bin/sh

set -eu

BUILD_MODE="jailbroken"
case "${1:-}" in
	"") ;;
	--jailbroken) BUILD_MODE="jailbroken" ;;
	*)
		echo "Usage: $0 [--jailbroken]" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
GECKO_DIST="$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios/dist"
IDEVICE_DIR="$ROOT_DIR/support/idevice"
IDEVICE_LIBRARY="$ROOT_DIR/browser/Reynard/JIT/RPPairing/libidevice_ffi.a"

. "$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"

"$ROOT_DIR/tools/firefox/prepare-firefox.sh" --check
"$ROOT_DIR/tools/firefox/gecko-artifact-manifest.sh" check "$GECKO_DIST"
"$ROOT_DIR/tools/development/build-idevice.sh"

if [ ! -f "$IDEVICE_LIBRARY" ]; then
	echo "Missing idevice library after build: $IDEVICE_LIBRARY" >&2
	exit 1
fi
if ! lipo "$IDEVICE_LIBRARY" -verify_arch arm64; then
	echo "The idevice library does not contain the required arm64 architecture." >&2
	exit 1
fi

XCODE_VERSION="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$XCCONFIG_PATH" "$DIST_DIR/Reynard.xcconfig"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD | cut -c1-7)
FIREFOX_SHA=$(git -C "$ROOT_DIR/engine/firefox" rev-parse HEAD)
IDEVICE_SHA=$(git -C "$IDEVICE_DIR" rev-parse HEAD)
sed -i '' "s/CURRENT_BUILD = .*/CURRENT_BUILD = $BUILD_SHA/" "$DIST_DIR/Reynard.xcconfig"

{
	echo "build_mode=$BUILD_MODE"
	echo "xcode_version=$XCODE_VERSION"
	echo "iphoneos_sdk_version=$SDK_VERSION"
	echo "reynard_revision=$(git -C "$ROOT_DIR" rev-parse HEAD)"
	echo "firefox_revision=$FIREFOX_SHA"
	echo "idevice_revision=$IDEVICE_SHA"
	echo "idevice_library_sha256=$(shasum -a 256 "$IDEVICE_LIBRARY" | awk '{print $1}')"
	echo "gecko_source_manifest_sha256=$(shasum -a 256 "$GECKO_DIST/reynard-source-manifest.txt" | awk '{print $1}')"
	echo "gecko_artifact_manifest_sha256=$(shasum -a 256 "$GECKO_DIST/reynard-gecko-artifact-manifest.txt" | awk '{print $1}')"
	for patch in "$ROOT_DIR"/patches/firefox/*.patch; do
		shasum -a 256 "$patch"
	done
} > "$DIST_DIR/source-revisions.txt"
echo "$BUILD_MODE" > "$DIST_DIR/build-mode"

xcodebuild archive \
	-scheme "Reynard" \
	-archivePath "$DIST_DIR/Reynard.xcarchive" \
	-project "$PROJECT_PATH" \
	-sdk iphoneos \
	-destination "generic/platform=iOS" \
	-configuration Release \
	-xcconfig "$DIST_DIR/Reynard.xcconfig" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY=""
