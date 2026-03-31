#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Stop if running
if [ -f /tmp/leafblower.pid ] && kill -0 "$(cat /tmp/leafblower.pid)" 2>/dev/null; then
    ./stop.sh
fi

# Start
./start.sh "$@"
