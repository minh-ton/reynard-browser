#!/bin/sh

set -eu

GECKO_DIST_BIN="${GECKO_DIST}/bin"
APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
GECKOVIEW_FW="${FRAMEWORKS_DIR}/GeckoView.framework"
GECKOVIEW_FW_FRAMEWORKS="${GECKOVIEW_FW}/Frameworks"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:-}}"
DEFAULT_THEME_SRC="${SRCROOT}/../engine/firefox/toolkit/mozapps/extensions/default-theme"

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}"

cp -fL "${GECKO_DIST_BIN}/"*.dylib "${FRAMEWORKS_DIR}/"
cp -fL "${GECKO_DIST_BIN}/XUL" "${GECKOVIEW_FW}/XUL"

if [ -n "${SIGN_IDENTITY}" ]; then
for file in "${GECKOVIEW_FW}/XUL" "${FRAMEWORKS_DIR}/"*.dylib; do
    if [ -f "${file}" ]; then
        codesign --force --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${file}"
    fi
done
fi

rsync -pvtrlL --delete --exclude "XUL" --exclude "*.dylib" --exclude "Test*" --exclude "test_*" --exclude "*_unittest" "${GECKO_DIST_BIN}/" "${GECKOVIEW_FW_FRAMEWORKS}"

mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}/default-theme"
cp -RfL "${DEFAULT_THEME_SRC}/" "${GECKOVIEW_FW_FRAMEWORKS}/default-theme/"
echo "resource default-theme file:default-theme/" >> "${GECKOVIEW_FW_FRAMEWORKS}/chrome.manifest"

if [ -n "${SIGN_IDENTITY}" ]; then
codesign --force --sign "${SIGN_IDENTITY}" "${GECKOVIEW_FW}"
fi
