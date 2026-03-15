# run-properly

This setup works by intercepting the physical keyboard on the Ubuntu host before VMware can hand the keystroke stream to the Windows guest. The interception is done by `keyd`, which is a low-level Linux key remapping daemon. A second layer, `keyd-application-mapper`, narrows the special behavior to the VMware window only. Because of that division of labor, normal host behavior stays intact outside VMware, while `Ctrl+Shift+D` and `Ctrl+Space` are reclaimed by the host when VMware is focused.

To use it correctly, think in terms of prerequisites first, then the normal path, then verification.

1. Make sure the host itself already has meanings for the shortcuts you want to reclaim. This setup passes the exact same key combinations back to Ubuntu. It does not invent new host actions. On the original machine, GNOME already had a custom shortcut for `Ctrl+Shift+D`, and IBus claimed `Ctrl+Space`.
2. Make sure you have logged out and logged back in after running the installer. That matters because the installer adds your user to the `keyd` group, and Linux only applies new group membership to a fresh login session.
3. Make sure the host session is Ubuntu GNOME on `X11`, not Wayland. This particular setup intentionally forces the application mapper down its `X11` path because VMware window detection is simpler and more predictable there.
4. Start your normal desktop session. The file [keyd-application-mapper.desktop](/home/cam/.config/autostart/keyd-application-mapper.desktop) should start the mapper automatically at login.
5. Start VMware Workstation and focus the Windows guest.
6. Press physical `Ctrl+Shift+D` or `Ctrl+Space`. The intended result is that Ubuntu receives the same combination first and runs the host-side shortcut action, while Windows does not receive that combination.

If you want to confirm that the pieces are running, use these checks:

```bash
systemctl status keyd
```

This command asks `systemd`, which is Ubuntu’s service manager, whether the low-level `keyd` daemon is installed and running.

```bash
pgrep -af keyd-application-mapper
```

This command looks for the application mapper process. If it is present, the VMware-only binding layer is active in your login session.

```bash
tail -n 50 "$HOME/.config/keyd/app.log"
```

This command reads the recent mapper log output. It is useful because the mapper writes window-focus changes and binding updates there after it is daemonized.

```bash
dconf dump /org/gnome/settings-daemon/plugins/media-keys/
```

This command shows GNOME’s media-key and custom-shortcut database. It is the authoritative place to verify host-side GNOME shortcuts such as `Ctrl+Shift+D`.

If `Ctrl+Shift+D` or `Ctrl+Space` still reaches Windows, the most common causes are that you have not logged out since installation, the mapper did not start, or the host session is not `X11`.
