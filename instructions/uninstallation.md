# uninstallation

Uninstallation is the reverse of the installation logic. First stop the live keyboard interception, then remove the user-session mapper, then delete the local application tree. The reason for that order is safety: you want the system to stop consuming keyboard events before you start deleting files that the running processes might still reference.

## 1. Stop and disable the system service

```bash
sudo systemctl disable --now keyd
```

This tells `systemd` to stop the `keyd` daemon immediately and to stop launching it automatically at boot.

## 2. Remove the service unit and the installed base config

```bash
sudo rm -f /etc/systemd/system/keyd.service
sudo rm -f /etc/keyd/default.conf
sudo systemctl daemon-reload
```

The first two commands remove the service definition and the installed config file. The third command makes `systemd` forget the removed unit file.

## 3. Remove the user from the `keyd` group

```bash
sudo gpasswd -d "$USER" keyd
```

This removes your user from the group that grants access to the `keyd` control socket.

If you are sure no other user or tool on the machine needs `keyd`, you can also remove the group itself:

```bash
sudo groupdel keyd
```

If this command fails because the group is still in use, leave the group in place. That is a harmless outcome.

## 4. Remove the user-session mapper files

```bash
rm -f "$HOME/.config/keyd/app.conf"
rm -f "$HOME/.config/autostart/keyd-application-mapper.desktop"
```

The first command removes the VMware-specific mapping rule from your home directory. The second removes the GNOME autostart entry so the mapper will not restart at login.

## 5. Remove the local application tree

```bash
rm -rf "$HOME/Applications/keyd-host-shortcuts"
```

This deletes the cloned source tree, the compiled binaries, the Python virtual environment, and the instruction files.

## 6. Log out and log back in

This final logout is important for the same reason it was important during installation. Your session needs to refresh its cached group membership and drop any remaining user-session state connected to the old setup.

## 7. Verify that the setup is gone

```bash
systemctl status keyd
pgrep -af keyd-application-mapper
```

The expected result is that `systemctl` reports the service is not found or inactive, and `pgrep` finds no mapper process.

If you want to remove only the VMware interception but keep `keyd` for other purposes, do not remove the service. In that narrower case, remove only `~/.config/keyd/app.conf` and `~/.config/autostart/keyd-application-mapper.desktop`, then log out and back in.
