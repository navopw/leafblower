#!/usr/bin/env bash
set -euo pipefail

APP_NAME="leafblower"
PID_FILE="/tmp/${APP_NAME}.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "$APP_NAME is already running (pid $(cat "$PID_FILE"))"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building frontend..."
(cd web && npm run build)

echo "Building backend..."
go build -o "$APP_NAME" ./cmd/leafblower

nohup ./"$APP_NAME" "$@" >"/tmp/${APP_NAME}.log" 2>&1 </dev/null &
echo $! > "$PID_FILE"
echo "$APP_NAME started (pid $!)"

for i in {1..10}; do
    if grep -q "listening on http" "/tmp/${APP_NAME}.log" 2>/dev/null; then
        grep "listening on http" "/tmp/${APP_NAME}.log"
        exit 0
    fi
    sleep 0.2
done
echo "Warning: could not determine URL from log"
