#!/usr/bin/env bash
set -euo pipefail

readonly BIN_PATH="$(swift build -c release "$@" --show-bin-path)"
swift build -c release "$@"

readonly APP="Leafblower.app"
rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH/Leafblower" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

echo "Built $APP"
