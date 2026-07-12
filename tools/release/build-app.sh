#!/bin/sh

set -eu

BUILD_MODE="jailbroken"
case "${1:-}" in
	"") ;;
	--jailbroken) BUILD_MODE="jailbroken" ;;
	--signed) BUILD_MODE="signed" ;;
	*)
		echo "Usage: $0 [--jailbroken|--signed]" >&2
		exit 2
		;;
esac

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"

"$ROOT_DIR/tools/firefox/apply-reynard-patches.sh"

XCODE_VERSION="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$XCCONFIG_PATH" "$DIST_DIR/Reynard.xcconfig"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD | cut -c1-7)
FIREFOX_SHA=$(git -C "$ROOT_DIR/engine/firefox" rev-parse HEAD)
sed -i '' "s/CURRENT_BUILD = .*/CURRENT_BUILD = $BUILD_SHA/" "$DIST_DIR/Reynard.xcconfig"

{
	echo "build_mode=$BUILD_MODE"
	echo "xcode_version=$XCODE_VERSION"
	echo "iphoneos_sdk_version=$SDK_VERSION"
	echo "reynard_revision=$(git -C "$ROOT_DIR" rev-parse HEAD)"
	echo "firefox_revision=$FIREFOX_SHA"
	for patch in "$ROOT_DIR"/patches/firefox/*.patch; do
		shasum -a 256 "$patch"
	done
} > "$DIST_DIR/source-revisions.txt"
echo "$BUILD_MODE" > "$DIST_DIR/build-mode"

if [ "$BUILD_MODE" = "jailbroken" ]; then
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
else
	xcodebuild archive \
		-scheme "Reynard" \
		-archivePath "$DIST_DIR/Reynard.xcarchive" \
		-project "$PROJECT_PATH" \
		-sdk iphoneos \
		-destination "generic/platform=iOS" \
		-configuration Release \
		-xcconfig "$DIST_DIR/Reynard.xcconfig"
fi
