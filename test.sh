#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Running walker benchmark test..."
go test -v -run TestWalkerHomeTime -count=1 ./internal/scan/ 2>&1 | tee /tmp/leafblower_bench.log

echo ""
echo "Extracting results:"
grep "Median time\|All runs\|Dirs:\|Files:" /tmp/leafblower_bench.log || true
