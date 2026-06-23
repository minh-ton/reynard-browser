#!/bin/sh

set -eu

GECKO_DIST_BIN="${GECKO_DIST}/bin"
APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
GECKOVIEW_FW="${FRAMEWORKS_DIR}/GeckoView.framework"
GECKOVIEW_FW_FRAMEWORKS="${GECKOVIEW_FW}/Frameworks"

DEFAULT_THEME_SRC="${SRCROOT}/../engine/firefox/toolkit/mozapps/extensions/default-theme"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:-}}"
SHOULD_CODE_SIGN=1
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ -z "${SIGN_IDENTITY}" ]; then
	SHOULD_CODE_SIGN=0
	echo "Skipping Gecko code signing in Copy Gecko Stuff"
fi

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}"

# copy dylibs and XUL, then sign
cp -fL "${GECKO_DIST_BIN}/"*.dylib "${FRAMEWORKS_DIR}/"
cp -fL "${GECKO_DIST_BIN}/XUL" "${GECKOVIEW_FW}/XUL"

for file in "${GECKOVIEW_FW}/XUL" "${FRAMEWORKS_DIR}/"*.dylib; do
	if [ -f "${file}" ]; then
		if [ "${SHOULD_CODE_SIGN}" = "1" ]; then
			codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${file}"
		fi
	fi
done

# copy the rest of the files, excluding the ones we already copied and the test files
rsync -pvtrlL --delete --exclude "XUL" --exclude "*.dylib" --exclude "Test*" --exclude "test_*" --exclude "*_unittest" "${GECKO_DIST_BIN}/" "${GECKOVIEW_FW_FRAMEWORKS}"

# default theme missing error fix
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}/default-theme"
cp -RfL "${DEFAULT_THEME_SRC}/" "${GECKOVIEW_FW_FRAMEWORKS}/default-theme/"
echo "resource default-theme file:default-theme/" >> "${GECKOVIEW_FW_FRAMEWORKS}/chrome.manifest"

# sign the GeckoView.framework
if [ "${SHOULD_CODE_SIGN}" = "1" ]; then
	codesign --force --sign "${SIGN_IDENTITY}" "${GECKOVIEW_FW}"
fi
