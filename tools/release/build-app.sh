#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
BUILD_XCCONFIG_PATH="$DIST_DIR/Reynard.xcconfig"

NO_SIGNING=false
NIGHTLY=false

for argument in "$@"; do
	case "$argument" in
		--no-signing)
			NO_SIGNING=true
			;;
		--nightly)
			NIGHTLY=true
			;;
		*) ;;
	esac
done

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$XCCONFIG_PATH" "$BUILD_XCCONFIG_PATH"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD | cut -c1-7)
sed -i '' -E \
	-e "s|^CURRENT_BUILD = .*|CURRENT_BUILD = $BUILD_SHA|" \
	"$BUILD_XCCONFIG_PATH"

if [ "$NIGHTLY" = true ]; then
	sed -i '' -E \
	-e 's|^(CURRENT_VERSION = [0-9.]+)$|\1-dev|' \
	-e 's|^APP_DISPLAY_NAME = .*|APP_DISPLAY_NAME = Reynard (Nightly)|' \
	"$BUILD_XCCONFIG_PATH"
fi

run_xcodebuild() {
	xcodebuild archive \
		-scheme "Reynard" \
		-archivePath "$DIST_DIR/Reynard.xcarchive" \
		-project "$PROJECT_PATH" \
		-sdk iphoneos \
		-arch arm64 \
		-configuration Release \
		-xcconfig "$BUILD_XCCONFIG_PATH" \
		"$@"
}

if [ "$NO_SIGNING" = true ]; then
	run_xcodebuild \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY="" \
		PROVISIONING_PROFILE_SPECIFIER=""
else
	run_xcodebuild
fi
