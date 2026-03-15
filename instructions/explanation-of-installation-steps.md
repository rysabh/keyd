# explanation-of-installation-steps

This setup has five pieces:

1. A local build of `keyd` in `$HOME/Applications/keyd-host-shortcuts`
2. A small base config in `config/default.conf`
3. A system service installed by `install-system.sh`
4. Two bridge scripts, one for each shortcut
5. A login-time binder script plus a GNOME autostart entry

What each file does:

## `config/default.conf`

This is the minimum base config needed by `keyd`. It tells `keyd` to manage all keyboards and defines the `control+shift` layer so `Ctrl+Shift+D` can be bound safely.

## `install-system.sh`

This is the one script that needs `sudo`. It:

1. Creates the `keyd` group if it does not already exist
2. Installs `/etc/keyd/default.conf`
3. Installs `/etc/systemd/system/keyd.service`
4. Adds your user to the `keyd` group
5. Enables and starts the `keyd` service

## `bridge-wsi-manual-toggle.sh`

This script handles `Ctrl+Shift+D`. `keyd` runs command bindings as root, so the bridge script switches back to your desktop user and then launches:

```bash
/home/cam/.local/bin/wsi-manual-toggle
```

It also writes a log file under `$HOME/.local/state/keyd-host-shortcuts/` so you can see whether the shortcut fired.

## `bridge-ulauncher-toggle.sh`

This script handles `Ctrl+Space`. It uses the same pattern as the first bridge script, but launches:

```bash
/usr/bin/ulauncher-toggle
```

It also writes a log file under `$HOME/.local/state/keyd-host-shortcuts/`.

## `apply-global-shortcuts.sh`

This script talks to the running `keyd` daemon and applies the two active shortcut bindings:

1. `control+shift.d = command(...bridge-wsi-manual-toggle.sh)`
2. `control.space = command(...bridge-ulauncher-toggle.sh)`

## `~/.config/autostart/keyd-application-mapper.desktop`

GNOME reads this file at login and runs `apply-global-shortcuts.sh`, so the shortcut bindings come back automatically every time you sign in.

Why logout/login is required:

The installer adds your user to the `keyd` group. Linux does not apply new group membership to an already-running desktop session, so you must log out and log back in once after installation.
