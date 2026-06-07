#!/usr/bin/env bash
set -euo pipefail

swift build -c release

APP="Leafblower.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Leafblower "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

echo "Built $APP"
