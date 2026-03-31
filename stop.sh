#!/usr/bin/env bash
set -euo pipefail

APP_NAME="leafblower"
PID_FILE="/tmp/${APP_NAME}.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "$APP_NAME is not running (no pid file)"
    exit 1
fi

PID="$(cat "$PID_FILE")"

if ! kill -0 "$PID" 2>/dev/null; then
    echo "$APP_NAME is not running (stale pid file)"
    rm -f "$PID_FILE"
    exit 1
fi

kill "$PID"
rm -f "$PID_FILE"
echo "$APP_NAME stopped (pid $PID)"
