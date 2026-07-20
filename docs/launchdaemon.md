# Privileged LED transport

MagSafe Dark 1.3.0 uses a root LaunchDaemon for SMC access. The menu-bar application and CLI never invoke `sudo` for LED reads or writes.

## Components

- `/usr/local/libexec/magsafe-led-daemon` runs as root under launchd.
- `/usr/local/libexec/magsafe-led-client` is the unprivileged Unix-socket client used by both the GUI and CLI.
- `/usr/local/libexec/magsafe-dark-cli` contains the CLI state, timer and Codex logic.
- `/usr/local/bin/magsafe-dark` configures the socket client and starts the CLI implementation.
- `/Library/LaunchDaemons/su.xyz.MagSafeDark.daemon.plist` starts and keeps the daemon alive.
- `/var/run/magsafe-dark.sock` is recreated whenever the daemon starts.

The daemon accepts only the fixed commands `ping`, `probe`, `status`, and the documented LED modes. It does not execute shell commands or accept arbitrary SMC keys. Connections are accepted only from root or the active console user, as verified with `getpeereid` and `/dev/console` ownership.

No sudoers rule is installed. The installer removes obsolete `/usr/local/libexec/magsafe-led-helper` and `/etc/sudoers.d/magsafe-dark` files left by older versions.

## Status checks

```bash
/usr/local/libexec/magsafe-led-client ping
/usr/local/libexec/magsafe-led-client probe
/usr/local/libexec/magsafe-led-client status
magsafe-dark diagnostics
```

Expected results on a supported Mac:

```text
pong
supported
0
```

The raw status value may differ from `0` when another mode is active.

## launchctl checks

```bash
sudo launchctl print system/su.xyz.MagSafeDark.daemon
ls -l /var/run/magsafe-dark.sock
```

Daemon logs are written to:

```text
/var/log/magsafe-dark-daemon.log
```

## Restart

```bash
sudo launchctl kickstart -k system/su.xyz.MagSafeDark.daemon
```

## Complete reinstall

```bash
zsh ./uninstall.sh
zsh ./install.sh
```
