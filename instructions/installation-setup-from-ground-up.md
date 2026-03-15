# installation-setup-from-ground-up

The goal is to make Ubuntu win the race for `Ctrl+Shift+D` and `Ctrl+Space` when VMware is focused, while still preserving the exact same key combinations on the host. The method is to install `keyd` from source in `$HOME/Applications/keyd-host-shortcuts`, define VMware-specific bindings that re-emit those shortcuts on the host, and start an application-aware mapper at login so the interception only applies to VMware windows.

This guide assumes the following environment:

1. The host is Ubuntu GNOME on `X11`.
2. VMware Workstation runs on the host and the guest is Windows.
3. Every machine has an `$HOME/Applications` directory.
4. The host already has, or will be given, real meanings for `Ctrl+Shift+D` and `Ctrl+Space`.

Before you begin, verify or create the host shortcuts themselves. This setup only forwards the exact key combinations to the host. If the host does not already use a given shortcut, then the forwarding will work but nothing visible will happen. On GNOME, the simplest way to check for custom shortcuts such as `Ctrl+Shift+D` is `Settings` -> `Keyboard` -> `View and Customize Shortcuts` -> `Custom Shortcuts`. For `Ctrl+Space`, also check any input-method framework, because IBus often claims that combination.

## 1. Install the build and runtime prerequisites

```bash
sudo apt update
sudo apt install -y git build-essential pkg-config python3-venv python3-pip
```

The first command refreshes Ubuntu’s package index so the package manager knows what versions are available. The second command installs the tools needed to clone the source code, compile `keyd`, and create a small Python virtual environment for the VMware window mapper.

## 2. Clone the source tree into `$HOME/Applications`

```bash
mkdir -p "$HOME/Applications"
cd "$HOME/Applications"
git clone https://github.com/rvaiya/keyd.git keyd-host-shortcuts
cd "$HOME/Applications/keyd-host-shortcuts"
```

These commands create the application directory if it does not already exist, switch into it, clone the upstream `keyd` source code, and then move into the cloned repository.

## 3. Build `keyd`

```bash
make
```

This compiles `keyd` from source and produces the main binaries in the local `bin/` directory. The important result is `$HOME/Applications/keyd-host-shortcuts/bin/keyd`.

## 4. Create a local Python environment for the application mapper

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install python-xlib
deactivate
```

The first command creates an isolated Python environment inside the project directory. The second command activates it for the current shell. The third command installs `python-xlib`, which lets the mapper inspect the focused `X11` window so it can apply rules only to VMware. The fourth command exits the virtual environment cleanly.

## 5. Create the base `keyd` config

Run this command exactly:

```bash
mkdir -p "$HOME/Applications/keyd-host-shortcuts/config"
cat > "$HOME/Applications/keyd-host-shortcuts/config/default.conf" <<'EOF'
# Minimal base keyd configuration.
#
# The main layer is left unchanged. We only define the composite layer below so
# the application mapper can attach Ctrl+Shift-specific bindings when VMware is
# the focused host window.

[ids]
*

[control+shift]
f24 = noop
EOF
```

This creates the configuration directory and writes the base `keyd` configuration file. The wildcard `*` in `[ids]` tells `keyd` to manage all keyboard devices it recognizes. The `[control+shift]` layer is defined so the mapper can later attach a `control+shift.d` rule safely.

## 6. Create the mapper launcher script

Run this command exactly:

```bash
cat > "$HOME/Applications/keyd-host-shortcuts/run-keyd-application-mapper.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
SOCKET_PATH="/var/run/keyd.socket"

export KEYD_BIN="$APP_DIR/bin/keyd"

# Force the mapper onto its X11 backend. On a GNOME-on-X11 session, that is
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
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/run-keyd-application-mapper.sh"
```

This writes the wrapper that starts the application mapper in the correct environment and then makes the script executable.

## 7. Create the privileged installer script

Run this command exactly:

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

printf '\nThe system service is installed. Log out and back in before using the mapper so %s picks up the keyd group.\n' "$TARGET_USER"
EOF

chmod +x "$HOME/Applications/keyd-host-shortcuts/install-system.sh"
```

This writes the script that performs the root-only part of the installation, then marks it executable.

## 8. Create the VMware-specific host forwarding rule

Run this command exactly:

```bash
mkdir -p "$HOME/.config/keyd"
cat > "$HOME/.config/keyd/app.conf" <<'EOF'
# Apply host-only shortcuts only when VMware Workstation is the focused host
# window. The normalized X11 class for Workstation is "vmware".

[vmware]

# Intercept physical Ctrl+Shift+D and re-emit the exact same combination on
# the host so Ubuntu can handle its own global shortcut before Windows sees it.
control+shift.d = C-S-d

# Intercept physical Ctrl+Space and re-emit the exact same combination on the
# host so host-side consumers such as IBus can handle it before Windows sees it.
control+space = C-space
EOF
```

This writes the mapper configuration in your home directory. The `[vmware]` section means the rule only activates when the focused window class is VMware.

## 9. Create the autostart entry

Run this command exactly:

```bash
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/keyd-application-mapper.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=keyd Application Mapper
Comment=Apply VMware-specific host shortcuts through keyd
Exec=/bin/sh -lc "$HOME/Applications/keyd-host-shortcuts/run-keyd-application-mapper.sh"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
```

This makes the application mapper start automatically when you log into GNOME.

## 10. Validate the base config before touching system files

```bash
"$HOME/Applications/keyd-host-shortcuts/bin/keyd" check "$HOME/Applications/keyd-host-shortcuts/config/default.conf"
```

This asks `keyd` to parse the base config and report errors. It is a cheap safety check before the privileged install step.

## 11. Perform the privileged installation

```bash
sudo "$HOME/Applications/keyd-host-shortcuts/install-system.sh"
```

This command runs the installer script with administrator privileges. That is necessary because Linux protects the keyboard event devices and because the `keyd` daemon must be installed as a system service.

## 12. Log out and log back in

Do this as a real desktop logout, not just by closing a terminal. The logout matters because your user must re-enter the session with membership in the `keyd` group.

## 13. Verify the final state

After logging back in, run:

```bash
systemctl status keyd
pgrep -af keyd-application-mapper
dconf dump /org/gnome/settings-daemon/plugins/media-keys/
```

The first command checks the low-level daemon. The second checks the VMware-aware mapper in your user session. The third verifies that the host really has the shortcuts you expect defined, whether through GNOME custom shortcuts, IBus, or another host-side consumer.

## 14. Test the behavior

1. Start VMware Workstation.
2. Focus the Windows guest.
3. Press physical `Ctrl+Shift+D` and physical `Ctrl+Space` separately.
4. Confirm that Ubuntu handles each host shortcut and Windows does not receive either one.
