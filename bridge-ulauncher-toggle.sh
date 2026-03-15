#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/ulauncher-toggle-bridge.log"

mkdir -p "$LOG_DIR"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

TARGET_USER="$(stat -c %U "$APP_DIR")"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_BIN="/usr/bin/ulauncher-toggle"
TARGET_PATH="$TARGET_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ ! -x "$TARGET_BIN" ]; then
    log "target command missing or not executable: $TARGET_BIN"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    exec "$TARGET_BIN"
fi

find_active_session() {
    while read -r sid uid user _rest; do
        [ "$uid" = "$TARGET_UID" ] || continue
        [ "$(loginctl show-session "$sid" -p Active --value 2>/dev/null)" = "yes" ] || continue
        [ "$(loginctl show-session "$sid" -p Class --value 2>/dev/null)" = "user" ] || continue
        echo "$sid"
        return 0
    done < <(loginctl list-sessions --no-legend)
    return 1
}

SESSION_ID="$(find_active_session || true)"
if [ -z "$SESSION_ID" ]; then
    log "no active graphical session found for user $TARGET_USER"
    exit 1
fi

LEADER_PID="$(loginctl show-session "$SESSION_ID" -p Leader --value 2>/dev/null || true)"
if [ -z "$LEADER_PID" ] || [ ! -r "/proc/$LEADER_PID/environ" ]; then
    log "cannot read environment for session $SESSION_ID leader $LEADER_PID"
    exit 1
fi

SESSION_ENV="$(tr '\0' '\n' < "/proc/$LEADER_PID/environ" || true)"
DISPLAY_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DISPLAY=//p' | head -n1)"
XDG_RUNTIME_DIR_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -n1)"
DBUS_SESSION_BUS_ADDRESS_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n1)"

if [ -z "$XDG_RUNTIME_DIR_VALUE" ]; then
    XDG_RUNTIME_DIR_VALUE="/run/user/$TARGET_UID"
fi

if [ -z "$DBUS_SESSION_BUS_ADDRESS_VALUE" ]; then
    DBUS_SESSION_BUS_ADDRESS_VALUE="unix:path=$XDG_RUNTIME_DIR_VALUE/bus"
fi

log "invoking $TARGET_BIN as $TARGET_USER via session $SESSION_ID leader $LEADER_PID display ${DISPLAY_VALUE:-<unset>}"

exec /usr/sbin/runuser -u "$TARGET_USER" -- env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    PATH="$TARGET_PATH" \
    DISPLAY="$DISPLAY_VALUE" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR_VALUE" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS_VALUE" \
    "$TARGET_BIN"
