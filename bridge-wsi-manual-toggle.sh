#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

TARGET_USER="$(stat -c %U "$APP_DIR")"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_BIN="$TARGET_HOME/.local/bin/wsi-manual-toggle"
TARGET_PATH="$TARGET_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
STATE_DIR="$TARGET_HOME/.local/state/keyd-host-shortcuts"
LOG_FILE="$STATE_DIR/wsi-manual-toggle-bridge.log"

mkdir -p "$STATE_DIR"

if [ ! -x "$TARGET_BIN" ]; then
    log "target command missing or not executable: $TARGET_BIN"
    exit 1
fi

# Allow direct user-side testing without needing the root-owned keyd path.
if [ "$(id -u)" -ne 0 ]; then
    exec "$TARGET_BIN"
fi

find_active_session() {
    local pattern pid env_dump

    for pattern in \
        'gnome-shell' \
        'gnome-session' \
        'ulauncher' \
        'plasmashell' \
        'xfce4-session' \
        'cinnamon-session' \
        'mate-session'
    do
        while read -r pid; do
            [ -n "$pid" ] || continue
            [ -r "/proc/$pid/environ" ] || continue
            env_dump="$(tr '\0' '\n' < "/proc/$pid/environ" || true)"
            if printf '%s\n' "$env_dump" | grep -Eq '^(DISPLAY|WAYLAND_DISPLAY)='; then
                echo "$pid"
                return 0
            fi
        done < <(ps -u "$TARGET_USER" -o pid= -o args= | awk -v pat="$pattern" '$0 ~ pat {print $1}')
    done

    while read -r pid; do
        [ -n "$pid" ] || continue
        [ -r "/proc/$pid/environ" ] || continue
        env_dump="$(tr '\0' '\n' < "/proc/$pid/environ" || true)"
        if printf '%s\n' "$env_dump" | grep -Eq '^(DISPLAY|WAYLAND_DISPLAY)='; then
            echo "$pid"
            return 0
        fi
    done < <(ps -u "$TARGET_USER" -o pid=)

    return 1
}

ENV_PID="$(find_active_session || true)"
if [ -z "$ENV_PID" ]; then
    log "no graphical process with DISPLAY or WAYLAND_DISPLAY found for user $TARGET_USER"
    exit 1
fi

if [ ! -r "/proc/$ENV_PID/environ" ]; then
    log "cannot read environment for pid $ENV_PID"
    exit 1
fi

SESSION_ENV="$(tr '\0' '\n' < "/proc/$ENV_PID/environ" || true)"
DISPLAY_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DISPLAY=//p' | head -n1)"
WAYLAND_DISPLAY_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^WAYLAND_DISPLAY=//p' | head -n1)"
XDG_RUNTIME_DIR_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -n1)"
DBUS_SESSION_BUS_ADDRESS_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n1)"
XAUTHORITY_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XAUTHORITY=//p' | head -n1)"
XDG_SESSION_TYPE_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XDG_SESSION_TYPE=//p' | head -n1)"

if [ -z "$XDG_RUNTIME_DIR_VALUE" ]; then
    XDG_RUNTIME_DIR_VALUE="/run/user/$TARGET_UID"
fi

if [ -z "$DBUS_SESSION_BUS_ADDRESS_VALUE" ]; then
    DBUS_SESSION_BUS_ADDRESS_VALUE="unix:path=$XDG_RUNTIME_DIR_VALUE/bus"
fi

if [ -z "$XAUTHORITY_VALUE" ] && [ -n "$DISPLAY_VALUE" ]; then
    XAUTHORITY_VALUE="$XDG_RUNTIME_DIR_VALUE/gdm/Xauthority"
fi

log "invoking $TARGET_BIN as $TARGET_USER via pid $ENV_PID display ${DISPLAY_VALUE:-<unset>} xauthority ${XAUTHORITY_VALUE:-<unset>}"

exec /usr/sbin/runuser -u "$TARGET_USER" -- env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    PATH="$TARGET_PATH" \
    DISPLAY="$DISPLAY_VALUE" \
    WAYLAND_DISPLAY="$WAYLAND_DISPLAY_VALUE" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR_VALUE" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS_VALUE" \
    XAUTHORITY="$XAUTHORITY_VALUE" \
    XDG_SESSION_TYPE="$XDG_SESSION_TYPE_VALUE" \
    "$TARGET_BIN"
