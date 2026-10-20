#!/usr/bin/env bash
# Launches a copy of Vermut.app from a temp folder while .build is renamed, so the
# app cannot fall back to absolute build-machine paths (e.g. SwiftPM's Bundle.module).
# Fails if the app exits within the timeout or logs a resource-bundle fatal error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$SCRIPT_DIR/Vermut.app}"
SECONDS_ALIVE="${SMOKE_SECONDS:-6}"
BUILD="$SCRIPT_DIR/.build"
HIDDEN="$SCRIPT_DIR/.build.smoke-hidden"

TMP="$(mktemp -d)"
PID=""
cleanup() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    if [ -d "$HIDDEN" ] && [ ! -e "$BUILD" ]; then mv "$HIDDEN" "$BUILD"; fi
    rm -rf "$TMP"
}
trap cleanup EXIT

ditto "$APP" "$TMP/Vermut.app"
if [ -d "$BUILD" ]; then mv "$BUILD" "$HIDDEN"; fi

LOG="$TMP/smoke.log"
"$TMP/Vermut.app/Contents/MacOS/Vermut" >"$LOG" 2>&1 &
PID=$!
sleep "$SECONDS_ALIVE"

if ! kill -0 "$PID" 2>/dev/null; then
    status=0; wait "$PID" || status=$?
    PID=""
    echo "Smoke test FAILED: app exited (status $status) with .build hidden:"
    cat "$LOG"
    exit 1
fi
if grep -qiE 'could not load resource bundle|Fatal error' "$LOG"; then
    echo "Smoke test FAILED: fatal error in log:"
    cat "$LOG"
    exit 1
fi
echo "Smoke test passed: app ran ${SECONDS_ALIVE}s from a temp folder with .build hidden"
