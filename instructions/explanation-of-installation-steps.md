# explanation-of-installation-steps

The installation sequence is easiest to understand if you keep three layers in mind. The first layer is the compiled `keyd` daemon, which sits near the Linux input subsystem and can see physical keyboard events before a focused application such as VMware consumes them. The second layer is a small application-aware mapper, which watches the currently focused host window and enables the special remapping only when that window belongs to VMware. The third layer is the host desktop itself, which still decides what `Ctrl+Shift+D` and `Ctrl+Space` actually mean. In other words, this setup changes who receives the shortcut first, but it does not change the shortcuts’ semantic meanings on the host.

Below is the reason for each instruction in the ground-up guide.

## `sudo apt update` and `sudo apt install ...`

These commands prepare the machine so it can build and run the toolchain. `git` downloads the source code from the upstream repository. `build-essential` provides `gcc`, `make`, and related build tools. `pkg-config` helps native builds discover compile flags when needed. `python3-venv` creates an isolated Python environment, and `python3-pip` installs the Python package needed by the mapper.

## `git clone https://github.com/rvaiya/keyd.git keyd-host-shortcuts`

This pulls the upstream `keyd` source code into `$HOME/Applications/keyd-host-shortcuts`. The renamed directory is intentional. It gives the project a stable local path that matches the rest of the instructions and keeps the installation self-contained in your application directory.

## `make`

This compiles `keyd` locally instead of installing a distribution package. That choice matters for two reasons. First, Ubuntu 22.04 does not ship `keyd` in its default repositories. Second, the user requested that downloaded or installed applications live under `$HOME/Applications` rather than being scattered directly into system locations.

## `python3 -m venv .venv`, activation, and `pip install python-xlib`

The `keyd-application-mapper` script is written in Python and needs `python-xlib` to inspect the focused `X11` window. A virtual environment keeps that dependency local to this project and avoids polluting the system Python installation. Activating the environment temporarily points `python` and `pip` at the local `.venv` directory, and `deactivate` returns the shell to normal afterward.

## `config/default.conf`

The base `keyd` config is intentionally small because its job is only to establish a valid global configuration that can later accept dynamic bindings. The `[ids]` section with `*` tells `keyd` to manage all keyboards it can identify. The `[control+shift]` layer with `f24 = noop` exists for a subtle reason: the application mapper attaches bindings dynamically, and it is safer to define the composite `control+shift` layer explicitly before trying to inject `control+shift.d = ...` rules into it.

## `run-keyd-application-mapper.sh`

This wrapper script does more than merely start a program.

1. It discovers its own directory at runtime so the setup works on any machine where the project lives at `$HOME/Applications/keyd-host-shortcuts`.
2. It exports `KEYD_BIN` so the mapper talks to the locally built `keyd` client rather than relying on a system-wide binary.
3. It forces `XDG_CURRENT_DESKTOP` to `x11` and unsets `GNOME_SETUP_DISPLAY`. That nudges the mapper away from its GNOME-extension path and toward the simpler direct `X11` monitor path, which is the better fit for a GNOME-on-`X11` VMware host.
4. It waits for `/var/run/keyd.socket`. That socket is the Unix-domain control channel the user-session mapper uses to tell the root-owned daemon what bindings should be active.
5. It runs `keyd bind reset` as a permission check. If your login session has not yet picked up membership in the `keyd` group, this command fails early and tells you to log out and back in.
6. It finally executes the mapper in daemon mode so it lives quietly in the background and writes logs to `~/.config/keyd/app.log`.

## `install-system.sh`

This script is the privileged half of the setup. It must run as root because Linux does not allow an unprivileged user to grab raw keyboard devices or create an input-remapping daemon at the system level.

1. It discovers its own directory, just like the mapper wrapper, so the service can point back to the local build under `$HOME/Applications`.
2. It derives the target user from `SUDO_USER` when available. That is important because the script itself runs as root, but the `keyd` group membership must be applied to the real desktop user.
3. It creates `/etc/keyd` if it does not already exist.
4. It creates the `keyd` group if necessary. That group is how unprivileged user-session tools are allowed to talk to the daemon’s control socket.
5. It installs the base config to `/etc/keyd/default.conf`. The daemon reads configs from `/etc/keyd`, not from the project directory.
6. It writes `/etc/systemd/system/keyd.service`. `systemd` is Ubuntu’s service manager, and this file tells `systemd` how to start `keyd` at boot.
7. It adds the desktop user to the `keyd` group so the user-session mapper can update the daemon’s bindings.
8. It reloads `systemd`, enables the service, starts it immediately, and then shows a short status summary.

## `~/.config/keyd/app.conf`

This file tells the application mapper what to do when a particular host window has focus. The `[vmware]` section matches the normalized `WM_CLASS` value of VMware Workstation on `X11`. The line `control+shift.d = C-S-d` means: when VMware is focused and the physical sequence `Ctrl+Shift+D` occurs, emit the exact same logical `Ctrl+Shift+D` into the host input stack. The line `control+space = C-space` does the same thing for `Ctrl+Space`. That is why the host can handle those shortcuts and Windows does not.

## `~/.config/autostart/keyd-application-mapper.desktop`

This file integrates the user-session part into GNOME login. GNOME reads `.desktop` files from `~/.config/autostart` and launches them automatically after you sign in. The command uses `/bin/sh -lc` so `$HOME` is expanded at runtime and the path remains portable across machines and usernames.

## `keyd check`

This validation step is a low-cost guardrail. If the base config contains a syntax error, it is better to discover that before installing the system service. A broken system-wide `keyd` config can make keyboard behavior confusing, so a dry parse is worth doing.

## `sudo .../install-system.sh`

This is where the machine crosses from “files prepared in the home directory” to “live keyboard interception is installed.” The script writes into `/etc`, manages a service with `systemctl`, and adjusts group membership. Those are all privileged operations.

## Logout and login

This step is not ceremonial. Group membership is cached in the login session. Until you log out and back in, the autostarted mapper may fail to talk to `/var/run/keyd.socket` even though the daemon itself is already running.

## Final verification commands

`systemctl status keyd` confirms the root-owned daemon is active. `pgrep -af keyd-application-mapper` confirms the user-session mapper is active. `dconf dump /org/gnome/settings-daemon/plugins/media-keys/` confirms that the host desktop actually has a meaning for shortcuts such as `Ctrl+Shift+D`, while input-method settings such as IBus may define `Ctrl+Space`. All three conditions must hold for the final behavior to match the design.
