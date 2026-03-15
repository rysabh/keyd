# installation-setup-from-ground-up

This guide installs the exact setup used here. The result is:

1. `Ctrl+Shift+D` runs `/home/cam/.local/bin/wsi-manual-toggle` on the Ubuntu host
2. `Ctrl+Space` runs `/usr/bin/ulauncher-toggle` on the Ubuntu host
3. Both shortcuts are caught by Ubuntu before VMware gives them to the Windows guest

Assumptions:

1. The host is Ubuntu
2. VMware Workstation is running on the host
3. The guest is Windows
4. `$HOME/Applications` exists, or you are willing to create it
5. `/home/cam/.local/bin/wsi-manual-toggle` already exists and works
6. `/usr/bin/ulauncher-toggle` already exists and works

If your `wsi-manual-toggle` command lives somewhere else on another PC, change `TARGET_BIN` in `bridge-wsi-manual-toggle.sh` before you use the setup.

## 1. Install build tools

```bash
sudo apt update
sudo apt install -y git build-essential pkg-config
```

This installs the tools needed to download and build `keyd`.

## 2. Clone `keyd` into `$HOME/Applications`

```bash
mkdir -p "$HOME/Applications"
cd "$HOME/Applications"
git clone https://github.com/rvaiya/keyd.git keyd-host-shortcuts
cd "$HOME/Applications/keyd-host-shortcuts"
```

This creates the application directory, downloads the source, and moves into it.

## 3. Build `keyd`

```bash
make
```

This creates the local `keyd` binary at:

```bash
$HOME/Applications/keyd-host-shortcuts/bin/keyd
```

## 4. Create the base config

```bash
mkdir -p "$HOME/Applications/keyd-host-shortcuts/config"
cat > "$HOME/Applications/keyd-host-shortcuts/config/default.conf" <<'EOF'
# Minimal base keyd configuration.

[ids]
*

[control+shift]
f24 = noop
EOF
```

This is the minimum config needed for the shortcuts used here.

## 5. Create the installer script

```bash
cat > "$HOME/Applications/keyd-host-shortcuts/install-system.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
CONFIG_DIR="/etc/keyd"
SYSTEMD_UNIT_PATH="/etc/systemd/system/keyd.service"
TARGET_USER="${SUDO_USER:-$(stat -c %U "$APP_DIR")}"

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run this script with sudo.\n' >&2
    exit 1
fi

if [ ! -x "$APP_DIR/bin/keyd" ]; then
    printf 'Expected built keyd binary at %s/bin/keyd.\n' "$APP_DIR" >&2
    exit 1
fi

install -d -m 755 "$CONFIG_DIR"

if ! getent group keyd >/dev/null; then
    groupadd --system keyd
fi

install -m 644 "$APP_DIR/config/default.conf" "$CONFIG_DIR/default.conf"

cat > "$SYSTEMD_UNIT_PATH" <<EOT
[Unit]
Description=keyd remapping daemon
After=local-fs.target

[Service]
Type=simple
ExecStart=$APP_DIR/bin/keyd

[Install]
WantedBy=multi-user.target
EOT

if ! id -nG "$TARGET_USER" | grep -qw keyd; then
    usermod -aG keyd "$TARGET_USER"
fi

systemctl daemon-reload
systemctl enable --now keyd
systemctl restart keyd

printf '\nkeyd service status:\n'
systemctl --no-pager --full status keyd | sed -n '1,12p'

printf '\nThe system service is installed. Log out and back in before using the shortcuts so %s picks up the keyd group.\n' "$TARGET_USER"
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/install-system.sh"
```

This script installs the system service and adds your user to the `keyd` group.

## 6. Create the `Ctrl+Shift+D` bridge

```bash
cat > "$HOME/Applications/keyd-host-shortcuts/bridge-wsi-manual-toggle.sh" <<'EOF'
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
DESKTOP_SESSION_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DESKTOP_SESSION=//p' | head -n1)"
XDG_CURRENT_DESKTOP_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XDG_CURRENT_DESKTOP=//p' | head -n1)"

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
    DESKTOP_SESSION="$DESKTOP_SESSION_VALUE" \
    XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP_VALUE" \
    "$TARGET_BIN"
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/bridge-wsi-manual-toggle.sh"
```

This script is what `keyd` runs when you press `Ctrl+Shift+D`.

## 7. Create the `Ctrl+Space` bridge

```bash
cat > "$HOME/Applications/keyd-host-shortcuts/bridge-ulauncher-toggle.sh" <<'EOF'
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
TARGET_BIN="/usr/bin/ulauncher-toggle"
TARGET_PATH="$TARGET_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
STATE_DIR="$TARGET_HOME/.local/state/keyd-host-shortcuts"
LOG_FILE="$STATE_DIR/ulauncher-toggle-bridge.log"

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
DESKTOP_SESSION_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^DESKTOP_SESSION=//p' | head -n1)"
XDG_CURRENT_DESKTOP_VALUE="$(printf '%s\n' "$SESSION_ENV" | sed -n 's/^XDG_CURRENT_DESKTOP=//p' | head -n1)"

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
    DESKTOP_SESSION="$DESKTOP_SESSION_VALUE" \
    XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP_VALUE" \
    "$TARGET_BIN"
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/bridge-ulauncher-toggle.sh"
```

This script is what `keyd` runs when you press `Ctrl+Space`. For Ulauncher, this direct command bridge is the preferred approach because `/usr/bin/ulauncher-toggle` already knows how to open the launcher correctly inside the host session.

## 8. Create the login-time binder

```bash
cat > "$HOME/Applications/keyd-host-shortcuts/apply-global-shortcuts.sh" <<'EOF'
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
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/apply-global-shortcuts.sh"
```

This script reapplies the two bindings every time you log in.

## 9. Create the GNOME autostart entry

```bash
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/keyd-application-mapper.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=keyd Host Shortcuts
Comment=Apply global host shortcut bridges through keyd
Exec=/bin/sh -lc "$HOME/Applications/keyd-host-shortcuts/apply-global-shortcuts.sh"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
```

This makes GNOME run the binder automatically at login.

## 10. Validate the base config

```bash
"$HOME/Applications/keyd-host-shortcuts/bin/keyd" check "$HOME/Applications/keyd-host-shortcuts/config/default.conf"
```

This checks for syntax errors before the privileged install step.

## 11. Install the system service

```bash
sudo "$HOME/Applications/keyd-host-shortcuts/install-system.sh"
```

This installs and starts `keyd`, and adds your user to the `keyd` group.

## 12. Log out and log back in

This step is required. Without it, your current desktop session does not know that your user was added to the `keyd` group.

## 13. Verify the setup

```bash
systemctl status keyd
id -nG
tail -n 50 "$HOME/.local/state/keyd-host-shortcuts/wsi-manual-toggle-bridge.log"
tail -n 50 "$HOME/.local/state/keyd-host-shortcuts/ulauncher-toggle-bridge.log"
```

What these commands verify:

1. `keyd` is running
2. Your login session includes the `keyd` group
3. The bridge scripts are being triggered

## 14. Test it

1. Start VMware Workstation.
2. Focus the Windows guest.
3. Press `Ctrl+Shift+D`.
4. Press `Ctrl+Space`.
5. Confirm that Ubuntu runs the host action and Windows does not receive the shortcut.
