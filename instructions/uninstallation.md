# uninstallation

To remove this setup cleanly, stop the service first, remove the autostart entry, and then delete the local files.

## 1. Stop and disable the service

```bash
sudo systemctl disable --now keyd
```

This stops the low-level keyboard service and prevents it from starting again at boot.

## 2. Remove the installed system files

```bash
sudo rm -f /etc/systemd/system/keyd.service
sudo rm -f /etc/keyd/default.conf
sudo systemctl daemon-reload
```

This removes the service unit and the installed base config, then tells `systemd` to forget the removed unit.

## 3. Remove your user from the `keyd` group

```bash
sudo gpasswd -d "$USER" keyd
```

If no one on the machine needs `keyd`, you can also remove the group:

```bash
sudo groupdel keyd
```

## 4. Remove the GNOME autostart entry

```bash
rm -f "$HOME/.config/autostart/keyd-application-mapper.desktop"
```

This stops Ubuntu from reapplying the shortcut bindings at login.

## 5. Remove the local application directory

```bash
rm -rf "$HOME/Applications/keyd-host-shortcuts"
```

This removes the local `keyd` build, the helper scripts, and these instruction files.

## 6. Remove the runtime state directory

```bash
rm -rf "$HOME/.local/state/keyd-host-shortcuts"
```

This removes the bridge log files that are written outside the repo.

## 7. Log out and log back in

This refreshes your desktop session so it drops the old `keyd` group membership and any leftover session state.

## 8. Verify removal

```bash
systemctl status keyd
id -nG
```

Expected result:

1. `keyd` is no longer active
2. Your fresh login session no longer depends on the `keyd` setup
