# run-properly

This setup makes Ubuntu handle two shortcuts before VMware can give them to the Windows guest:

1. `Ctrl+Shift+D`
2. `Ctrl+Space`

It works by running a low-level `keyd` service on the host. That service catches the physical key press and runs a host-side bridge script.

The active shortcuts are:

1. `Ctrl+Shift+D` -> `/home/cam/.local/bin/wsi-manual-toggle`
2. `Ctrl+Space` -> `/usr/bin/ulauncher-toggle`

To use the setup:

1. Make sure both host commands work when you run them directly.
2. Make sure you have already run the installer script once:

```bash
sudo "$HOME/Applications/keyd-host-shortcuts/install-system.sh"
```

3. Log out and log back in once after running the installer. This is required because your user must pick up membership in the `keyd` group.
4. Log into Ubuntu normally. The autostart entry will apply the shortcut bindings automatically.
5. Start VMware Workstation.
6. Focus the Windows guest.
7. Press `Ctrl+Shift+D` or `Ctrl+Space`.

Expected result:

1. Ubuntu runs the matching host action.
2. Windows does not receive that shortcut.

Quick checks:

```bash
systemctl status keyd
id -nG
tail -n 50 "$HOME/.local/state/keyd-host-shortcuts/wsi-manual-toggle-bridge.log"
tail -n 50 "$HOME/.local/state/keyd-host-shortcuts/ulauncher-toggle-bridge.log"
```

What these commands tell you:

1. `systemctl status keyd` confirms that the low-level service is running.
2. `id -nG` confirms that your user session includes the `keyd` group.
3. The two `tail` commands show whether the bridge scripts were triggered.
