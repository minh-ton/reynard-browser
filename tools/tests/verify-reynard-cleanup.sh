#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/.build/firefox"
TEST_BINARY="${TMPDIR:-/tmp}/reynard-website-mode-host-tests"
NEW_TAB_TEST_BINARY="${TMPDIR:-/tmp}/reynard-new-tab-keyboard-policy-tests"
EXTERNAL_APP_TEST_BINARY="${TMPDIR:-/tmp}/reynard-external-app-link-policy-tests"
EXTERNAL_APP_ROUTER_TEST_BINARY="${TMPDIR:-/tmp}/reynard-external-app-link-router-tests"
NAVIGATION_HISTORY_TEST_BINARY="${TMPDIR:-/tmp}/reynard-navigation-history-tests"
TOOLBAR_LAYOUT_TEST_BINARY="${TMPDIR:-/tmp}/reynard-toolbar-layout-tests"
IMAGE_DECODE_TEST_BINARY="${TMPDIR:-/tmp}/reynard-image-decode-tests"
ADDON_STAGING_TEST_BINARY="${TMPDIR:-/tmp}/reynard-addon-staging-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/reynard-swift-module-cache"

"$ROOT_DIR/tools/firefox/prepare-firefox.sh"

if [ -z "${REYNARD_DIFF_BASE:-}" ]; then
	REYNARD_DIFF_BASE="$(git -C "$ROOT_DIR" merge-base HEAD upstream/main 2>/dev/null || git -C "$ROOT_DIR" rev-parse HEAD^)"
	export REYNARD_DIFF_BASE
fi

node --check "$FIREFOX_DIR/mobile/shared/components/extensions/ext-tabs.js"
node --check "$FIREFOX_DIR/mobile/shared/components/extensions/ext-downloads.js"
node --check "$FIREFOX_DIR/mobile/shared/components/extensions/FullPageCaptureCompat.sys.mjs"
node --check "$FIREFOX_DIR/toolkit/components/extensions/child/ext-storage.js"
node "$SCRIPT_DIR/FullPageCaptureCompatTests.mjs"
node "$SCRIPT_DIR/verify-localizations.mjs"

sh -n \
	"$ROOT_DIR/tools/development/apply-patches.sh" \
	"$ROOT_DIR/tools/development/build-gecko.sh" \
	"$ROOT_DIR/tools/firefox/apply-reynard-patches.sh" \
	"$ROOT_DIR/tools/firefox/gecko-artifact-manifest.sh" \
	"$ROOT_DIR/tools/firefox/prepare-firefox.sh" \
	"$ROOT_DIR/tools/release/build-app.sh" \
	"$ROOT_DIR/tools/release/create-ipa.sh" \
	"$ROOT_DIR/tools/xcode/use-xcode-26.2.sh"
zsh -n "$ROOT_DIR/tools/development/build-idevice.sh"

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

if rg -q 'UIImage\(contentsOfFile:' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageViewController.swift" ||
	! rg -q 'CGImageSourceCreateThumbnailAtIndex' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageViewController.swift" ||
	! rg -q 'maximumPixelCount' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageDecodePolicy.swift"; then
	echo "Downloaded images are not decoded with bounded ImageIO memory use." >&2
	exit 1
fi

if ! rg -q 'AddonPackageStaging\.remove\(stagedURL\)' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/BrowserViewController+AddressBar.swift" ||
	! rg -q 'AddonPackageStaging\.remove\(stagedPackageURL\)' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Settings/Sections/General/Addons/AddonsPreferencesViewController.swift" ||
	! rg -q 'AddonPackageStaging\.removeStaleFiles\(\)' \
	"$ROOT_DIR/browser/Reynard/AppDelegate.swift"; then
	echo "Temporary add-on packages are not cleaned up on every path." >&2
	exit 1
fi

if rg -q 'AddressBarZoomDropdown|showsZoomButton|addressBarDidRequestPageZoom|showPageZoomDropdown' \
	"$ROOT_DIR/browser/Reynard/Client/Interface"; then
	echo "Obsolete address-bar zoom controls remain." >&2
	exit 1
fi

if ! rg -q 'BottomToolbarLayoutPolicy\.visibleActionCount' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Chrome/Toolbar/BottomToolbar.swift" ||
	rg -q 'displayedOverflowActions|overflowButton|overflowTapped' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Chrome/Toolbar/BottomToolbar.swift"; then
	echo "The static 10-action toolbar implementation is incomplete." >&2
	exit 1
fi

if ! rg -q 'addressBar\.setPageMenuIndicatesUpdate\(hasUpdate\)' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Chrome/BrowserChrome.swift" ||
	! rg -q 'pageMenuUpdateBadge' \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Chrome/AddressBar/AddressBar.swift"; then
	echo "The browser update indicator is not wired to the page menu." >&2
	exit 1
fi

AUTOCORRECTION_PATCH="$ROOT_DIR/patches/firefox/0004-uikit-autocorrection-state.patch"
if ! rg -q 'kPendingKeyboardEditLifetime' \
		"$AUTOCORRECTION_PATCH" ||
	! rg -q 'pendingKeyboardEditSelection:&pendingSelection' \
		"$AUTOCORRECTION_PATCH" ||
	! rg -q 'setPendingKeyboardEditSelection:NSMakeRange' \
		"$AUTOCORRECTION_PATCH" ||
	! rg -q 'handler->SetSelectedRange\(pendingSelection\)' \
	"$AUTOCORRECTION_PATCH" ||
	! rg -q 'clearPendingKeyboardEditSelection' \
		"$AUTOCORRECTION_PATCH" ||
	rg -q 'ReynardTextInput|mPendingKeyboardEditSourceSelection|invalidatePendingKeyboardEditSelection' \
		"$AUTOCORRECTION_PATCH"; then
	echo "The focused UIKit autocorrection state fix is incomplete." >&2
	exit 1
fi

if ! rg -q 'export WASM_CC WASM_CXX' \
	"$ROOT_DIR/tools/development/build-gecko.sh"; then
	echo "The Gecko build does not preserve its required WebAssembly compiler." >&2
	exit 1
fi

EXTERNAL_LINK_PATCH="$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch"
if ! rg -q '!event\.isTrusted' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'hasValidTransientUserGestureActivation' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'event\.defaultPrevented' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'this\.contentWindow\.top !== this\.contentWindow' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'destination\.scheme !== "http"' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'GeckoView:LinkActivated' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'GeckoView:ExternalProtocol' "$EXTERNAL_LINK_PATCH" ||
	! rg -q 'func onLinkActivated' \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/TabManagerImpl.swift"; then
	echo "The trusted web-link activation bridge is incomplete." >&2
	exit 1
fi

if rg -q 'ExternalAppLinkDiagnostics|NavigationEventDiagnostics|ReynardExternalLinks\.log|ReynardNavigationEvents\.log' \
	"$ROOT_DIR/browser/GeckoView" "$ROOT_DIR/browser/Reynard"; then
	echo "Temporary external-link diagnostics remain in the application." >&2
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

if ! rg -q 'tools/development/build-idevice\.sh' \
	"$ROOT_DIR/tools/release/build-app.sh" ||
	! rg -q 'lipo "\$IDEVICE_LIBRARY" -verify_arch arm64' \
	"$ROOT_DIR/tools/release/build-app.sh" ||
	! rg -q 'idevice_library_sha256=' \
	"$ROOT_DIR/tools/release/build-app.sh"; then
	echo "The release build does not reproduce and record its idevice library." >&2
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
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/ExternalAppLinkRouter.swift" \
	"$SCRIPT_DIR/ExternalAppLinkRouterTests.swift" \
	-o "$EXTERNAL_APP_ROUTER_TEST_BINARY"
"$EXTERNAL_APP_ROUTER_TEST_BINARY"
rm -f "$EXTERNAL_APP_ROUTER_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/SessionManagement/Navigation/NavigationState.swift" \
	"$ROOT_DIR/browser/Reynard/Client/Stores/NavigationHistoryStore.swift" \
	"$ROOT_DIR/browser/Reynard/Client/SessionManagement/Navigation/NavigationHistory.swift" \
	"$SCRIPT_DIR/NavigationHistoryTests.swift" \
	-o "$NAVIGATION_HISTORY_TEST_BINARY"
"$NAVIGATION_HISTORY_TEST_BINARY"
rm -f "$NAVIGATION_HISTORY_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Chrome/Toolbar/BottomToolbarLayoutPolicy.swift" \
	"$SCRIPT_DIR/BottomToolbarLayoutPolicyTests.swift" \
	-o "$TOOLBAR_LAYOUT_TEST_BINARY"
"$TOOLBAR_LAYOUT_TEST_BINARY"
rm -f "$TOOLBAR_LAYOUT_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Downloads/DownloadImageDecodePolicy.swift" \
	"$SCRIPT_DIR/DownloadImageDecodePolicyTests.swift" \
	-o "$IMAGE_DECODE_TEST_BINARY"
"$IMAGE_DECODE_TEST_BINARY"
rm -f "$IMAGE_DECODE_TEST_BINARY"

swiftc \
	-module-cache-path "$MODULE_CACHE" \
	"$ROOT_DIR/browser/Reynard/Client/Interface/Library/Settings/Sections/General/Addons/AddonPackageStaging.swift" \
	"$SCRIPT_DIR/AddonPackageStagingTests.swift" \
	-o "$ADDON_STAGING_TEST_BINARY"
"$ADDON_STAGING_TEST_BINARY"
rm -f "$ADDON_STAGING_TEST_BINARY"

if ! rg -q 'universalLinksOnly' \
	"$ROOT_DIR/browser/Reynard/Client/TabManagement/TabManagerImpl.swift" ||
	! rg -q 'disposition == \.opened \? \.deny : \.allow' \
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
	! rg -q 'GeckoView:ExternalProtocol' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch" ||
	! rg -q 'if \(dispatcher\)' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch"; then
	echo "The native UIKit external-protocol bridge is incomplete." >&2
	exit 1
fi

if rg -q 'OnTrustedLinkClick|default\.BrowsingSettings\.openLinksInApps|UIApplication|NSUserDefaults|comgooglemaps|com\.reddit\.frontpage|GoogleMapsURLFromAndroidIntent' \
	"$ROOT_DIR/patches/firefox/0006-uikit-external-app-links.patch"; then
	echo "Product-specific external app-link policy remains in Firefox." >&2
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
