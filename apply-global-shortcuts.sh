#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
SOCKET_PATH="/var/run/keyd.socket"
KEYD_BIN="$APP_DIR/bin/keyd"
BRIDGE="$APP_DIR/bridge-wsi-manual-toggle.sh"
ULAUNCHER_BRIDGE="$APP_DIR/bridge-ulauncher-toggle.sh"

for _ in $(seq 1 60); do
    if [ -S "$SOCKET_PATH" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "$SOCKET_PATH" ]; then
    printf 'keyd socket %s did not appear within 60 seconds.\n' "$SOCKET_PATH" >&2
    exit 1
fi

"$KEYD_BIN" bind reset \
    "control+shift.d = command($BRIDGE)" \
    "control.space = command($ULAUNCHER_BRIDGE)"
