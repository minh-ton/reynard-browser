#!/bin/sh

REYNARD_XCODE_APP="${REYNARD_XCODE_APP:-/Applications/Xcode-26.2.0.app}"
REYNARD_XCODE_DEVELOPER_DIR="$REYNARD_XCODE_APP/Contents/Developer"

if [ ! -x "$REYNARD_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
	echo "Xcode 26.2 is unavailable at $REYNARD_XCODE_APP" >&2
	echo "Set REYNARD_XCODE_APP to the Xcode 26.2 application path." >&2
	exit 1
fi

export DEVELOPER_DIR="$REYNARD_XCODE_DEVELOPER_DIR"

REYNARD_XCODE_VERSION="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
if [ "$REYNARD_XCODE_VERSION" != "26.2" ]; then
	echo "Reynard releases require Xcode 26.2, but $REYNARD_XCODE_APP provides $REYNARD_XCODE_VERSION." >&2
	exit 1
fi

export REYNARD_XCODE_APP REYNARD_XCODE_VERSION
