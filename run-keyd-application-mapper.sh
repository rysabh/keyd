#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
SOCKET_PATH="/var/run/keyd.socket"

export KEYD_BIN="$APP_DIR/bin/keyd"

# Force the mapper onto its X11 backend. On this GNOME-on-X11 session, that is
# simpler and avoids the GNOME extension path entirely.
export XDG_CURRENT_DESKTOP="x11"
unset GNOME_SETUP_DISPLAY || true

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

if ! "$KEYD_BIN" bind reset >/dev/null 2>&1; then
    printf 'Cannot access %s. If keyd was just installed, log out and back in so the keyd group takes effect.\n' "$SOCKET_PATH" >&2
    exit 1
fi

exec "$APP_DIR/.venv/bin/python" "$APP_DIR/bin/keyd-application-mapper" -d
