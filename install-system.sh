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

cat > "$SYSTEMD_UNIT_PATH" <<EOF
[Unit]
Description=keyd remapping daemon
After=local-fs.target

[Service]
Type=simple
ExecStart=$APP_DIR/bin/keyd

[Install]
WantedBy=multi-user.target
EOF

if ! id -nG "$TARGET_USER" | grep -qw keyd; then
    usermod -aG keyd "$TARGET_USER"
fi

systemctl daemon-reload
systemctl enable --now keyd
systemctl restart keyd

printf '\nkeyd service status:\n'
systemctl --no-pager --full status keyd | sed -n '1,12p'

printf '\nThe system service is installed. Log out and back in before using the mapper so %s picks up the keyd group.\n' "$TARGET_USER"
