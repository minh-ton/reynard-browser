#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
TEST_BINARY="${TMPDIR:-/tmp}/reynard-website-mode-host-tests"
NEW_TAB_TEST_BINARY="${TMPDIR:-/tmp}/reynard-new-tab-keyboard-policy-tests"
EXTERNAL_APP_TEST_BINARY="${TMPDIR:-/tmp}/reynard-external-app-link-policy-tests"
EXTERNAL_APP_COORDINATOR_TEST_BINARY="${TMPDIR:-/tmp}/reynard-external-app-link-coordinator-tests"
NAVIGATION_HISTORY_TEST_BINARY="${TMPDIR:-/tmp}/reynard-navigation-history-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/reynard-swift-module-cache"

node --check "$FIREFOX_DIR/mobile/shared/components/extensions/ext-tabs.js"
node --check "$FIREFOX_DIR/mobile/shared/components/extensions/ext-downloads.js"
node --check "$FIREFOX_DIR/mobile/shared/components/extensions/FullPageCaptureCompat.sys.mjs"
node --check "$FIREFOX_DIR/toolkit/components/extensions/child/ext-storage.js"
node "$SCRIPT_DIR/FullPageCaptureCompatTests.mjs"

sh -n \
	"$ROOT_DIR/tools/development/apply-patches.sh" \
	"$ROOT_DIR/tools/development/build-gecko.sh" \
	"$ROOT_DIR/tools/firefox/apply-reynard-patches.sh" \
	"$ROOT_DIR/tools/firefox/gecko-artifact-manifest.sh" \
	"$ROOT_DIR/tools/firefox/prepare-firefox.sh" \
	"$ROOT_DIR/tools/release/build-app.sh" \
	"$ROOT_DIR/tools/release/create-ipa.sh" \
	"$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"

"$ROOT_DIR/tools/firefox/prepare-firefox.sh" --check

if rg -q 'Reynard-(AddonDebug|DownloadDebug|ClipboardDebug|AddonSelectionDebug)\.log|Addon(File|Clipboard|Selection)Diagnostics' \
	"$FIREFOX_DIR/mobile/shared/components/extensions/ext-tabs.js" \
	"$FIREFOX_DIR/mobile/shared/components/extensions/ext-downloads.js" \
	"$ROOT_DIR/browser/GeckoView/Addons/AddonRuntimeEvents.swift"; then
	echo "Temporary add-on diagnostics remain in production code." >&2
	exit 1
fi

if rg -q 'mimeType: "image/png"' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Addons/AddonCoordinator.swift"; then
	echo "Add-on downloads still force every MIME type to image/png." >&2
	exit 1
fi

if ! rg -q 'QLPreviewControllerDataSource' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImagePreview.swift" ||
	! rg -q 'maximumZoomMultiplier' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageViewController.swift" ||
	! rg -q 'UIActivityViewController' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageViewController.swift" ||
	! rg -q 'QLPreviewController\.canPreview' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadsViewController.swift"; then
	echo "The native downloaded-image preview route is incomplete." >&2
	exit 1
fi

if ! rg -q 'Reynard-TextInputDebug\.log' \
	"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'isSecureTextEntry' \
	"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'ReynardTextInputDiagnosticsEnabled' \
	"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'mPendingKeyboardEditSourceSelection' \
		"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'sourceSelection:sourceSelection' \
		"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'invalidatePendingKeyboardEditSelection' \
		"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'handler->SetSelectedRange\(pendingSelection\)' \
	"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch" ||
	! rg -q 'clearPendingKeyboardEditSelection' \
	"$ROOT_DIR/patches/firefox/0004-uikit-text-input-diagnostics.patch"; then
	echo "The bounded, secure-field-safe website text input diagnostics are incomplete." >&2
	exit 1
fi

if ! rg -q 'export WASM_CC WASM_CXX' \
	"$ROOT_DIR/tools/development/build-gecko.sh"; then
	echo "The Gecko build does not preserve its required WebAssembly compiler." >&2
	exit 1
fi

if "$ROOT_DIR/tools/release/create-ipa.sh" --invalid >/dev/null 2>&1; then
	echo "create-ipa.sh accepted an unsupported packaging mode." >&2
	exit 1
fi

if "$ROOT_DIR/tools/release/build-app.sh" --signed >/dev/null 2>&1; then
	echo "build-app.sh accepted the unsupported signed packaging mode." >&2
	exit 1
fi

xcrun --find swiftc >/dev/null
mkdir -p "$MODULE_CACHE"
swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/SessionManagement/Settings/WebsiteMode/WebsiteModeHost.swift" \
	"$SCRIPT_DIR/WebsiteModeHostTests.swift" \
	-o "$TEST_BINARY"
"$TEST_BINARY"
rm -f "$TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Settings/Sections/General/NewTab/NewTabDisplayOption.swift" \
	"$SCRIPT_DIR/NewTabKeyboardPolicyTests.swift" \
	-o "$NEW_TAB_TEST_BINARY"
"$NEW_TAB_TEST_BINARY"
rm -f "$NEW_TAB_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/ExternalAppLinkPolicy.swift" \
	"$SCRIPT_DIR/ExternalAppLinkPolicyTests.swift" \
	-o "$EXTERNAL_APP_TEST_BINARY"
"$EXTERNAL_APP_TEST_BINARY"
rm -f "$EXTERNAL_APP_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/ExternalAppLinkPolicy.swift" \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/ExternalAppLinkCoordinator.swift" \
	"$SCRIPT_DIR/ExternalAppLinkCoordinatorTests.swift" \
	-o "$EXTERNAL_APP_COORDINATOR_TEST_BINARY"
"$EXTERNAL_APP_COORDINATOR_TEST_BINARY"
rm -f "$EXTERNAL_APP_COORDINATOR_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/SessionManagement/Navigation/NavigationState.swift" \
	"$ROOT_DIR/browser/Reynard/Client/Stores/NavigationHistoryStore.swift" \
	"$ROOT_DIR/browser/Reynard/Client/SessionManagement/Navigation/NavigationHistory.swift" \
	"$SCRIPT_DIR/NavigationHistoryTests.swift" \
	-o "$NAVIGATION_HISTORY_TEST_BINARY"
"$NAVIGATION_HISTORY_TEST_BINARY"
rm -f "$NAVIGATION_HISTORY_TEST_BINARY"

if ! rg -q 'universalLinksOnly' \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/TabManagerImpl.swift" ||
	! rg -q 'return opened \? \.deny : \.allow' \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/TabManagerImpl.swift"; then
	echo "External app links do not preserve a safe web fallback." >&2
	exit 1
fi

if rg -q 'ExternalAppLinkDiagnostics|Reynard-ExternalAppLinks\.log' \
	"$ROOT_DIR/browser"; then
	echo "Temporary external app-link diagnostics remain in production code." >&2
	exit 1
fi

if ! rg -q 'key\("BrowsingSettings", "openLinksInApps"\): true' \
	"$ROOT_DIR/browser/Reynard/Client/Preferences/BrowserPreferences.swift" ||
	! rg -q 'Prefs\.BrowsingSettings\.openLinksInApps' \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/TabManagerImpl.swift" ||
	! rg -q 'Open Links in Apps' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Settings/Sections/General/Browsing/BrowsingPreferencesViewController.swift"; then
	echo "The external app-link preference is not wired end to end." >&2
	exit 1
fi

if ! rg -q 'OSProtocolHandlerExists' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'LoadUriInternal' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'Reynard\.Browsing\.openLinksInApps' \
		"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'ReynardSupportsExternalScheme' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'com\.reddit\.frontpage' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'if \(dispatcher\)' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch"; then
	echo "The native UIKit external-protocol bridge is incomplete." >&2
	exit 1
fi

if rg -q 'OnTrustedLinkClick|default\.BrowsingSettings\.openLinksInApps' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch"; then
	echo "A duplicate or profile-specific external app-link path remains." >&2
	exit 1
fi

if ! rg -q 'scheduleAutomaticKeyboardFocusForNewTab' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/BrowserViewController+BrowserActions.swift" ||
	! rg -q 'scheduleAutomaticKeyboardFocusForNewTab' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/BrowserViewController+TabPresentation.swift" ||
	! rg -q 'tabManager\.selectedTab\?\.id == tabID' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/BrowserViewController+BrowserActions.swift" ||
	! rg -q 'stablePassesRemaining' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/BrowserViewController+BrowserActions.swift"; then
	echo "Foreground new-tab keyboard focus is not consistently guarded." >&2
	exit 1
fi

DIFF_BASE="${REYNARD_DIFF_BASE:-}"
if [ -z "$DIFF_BASE" ]; then
	for candidate in upstream/main origin/main main; do
		if git -C "$ROOT_DIR" rev-parse -q --verify "$candidate^{commit}" >/dev/null; then
			DIFF_BASE="$(git -C "$ROOT_DIR" merge-base HEAD "$candidate")"
			break
		fi
	done
fi

if [ -z "$DIFF_BASE" ]; then
	echo "Unable to determine the base revision for committed diff verification." >&2
	echo "Set REYNARD_DIFF_BASE to the pull request base revision." >&2
	exit 1
fi

git -C "$ROOT_DIR" diff --check "$DIFF_BASE...HEAD"
git -C "$ROOT_DIR" diff --check
echo "Reynard cleanup verification passed"
