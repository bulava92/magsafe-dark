# MagSafe Dark

[Русская версия](README_RU.md)

[Support the project](https://boosty.to/smd.monster/donate)

MagSafe Dark is a macOS menu-bar app for controlling the LED on a MagSafe connector.

It can turn the LED off, return control to macOS, show green or orange, run temporary effects, follow a weekly schedule, and display the state of Codex CLI tasks.

> MagSafe Dark uses the undocumented Apple SMC key `ACLC`. A macOS or firmware update may change or disable this behavior.

## Requirements

- macOS 13 or newer
- Apple Silicon MacBook with MagSafe 3

The app has been tested on a MacBook Pro M5. Support can be checked after installation:

```bash
magsafe-dark probe
```

Expected result:

```text
supported
```

## Main features

- Turn the MagSafe LED off or return it to normal macOS control.
- Show green, orange, a single indication, or blinking effects.
- Start a temporary mode for a selected duration.
- Create a weekly schedule for different times and days.
- Use separate LED modes for Codex work, success, and error states.
- React to charger connection and disconnection through native IOKit power-source notifications.
- Show battery percentage, charging state, and estimated charge completion in the menu bar.
- Choose a battery or lightbulb status glyph.
- Start automatically when you sign in.
- View diagnostics and logs from the app menu.

## Installation

### Installer package

Build and validate a local unsigned package:

```bash
zsh ./scripts/check-release.sh --package
open build
```

The package is written to:

```text
build/MagSafeDark-<version>-unsigned.pkg
```

### Installation from source

```bash
git clone https://github.com/bulava92/magsafe-dark.git
cd magsafe-dark
zsh ./scripts/check-release.sh
zsh ./install.sh
```

For an existing checkout:

```bash
cd ~/Projects/magsafe-dark
git pull
zsh ./scripts/check-release.sh
zsh ./install.sh
```

The installer asks for the administrator password once. After installation, normal app and command-line use does not require `sudo`.

The app is installed as:

```text
/Applications/MagSafe Dark.app
```

## Using the menu-bar app

Open **MagSafe Dark** from Applications. From the menu you can:

- choose an LED mode;
- start or cancel a timer;
- configure the weekly schedule;
- configure Codex indication;
- enable launch at login;
- choose the menu-bar status glyph and icon style;
- show battery percentage, charging state, and charge completion;
- open diagnostics and logs;
- check for updates.

Keyboard shortcuts while the menu is open:

- `⌘⇧0` — switch between Off and System mode;
- `⌘⇧G` — Green;
- `⌘⇧O` — Orange;
- `⌘Q` — Quit.

## LED modes

| Mode | Description |
|---|---|
| System | macOS controls the LED normally |
| Off | LED stays off |
| Green | solid green |
| Orange | solid orange |
| Single indication | one short indication |
| Slow blink | slow orange blinking |
| Fast blink | fast orange blinking |
| Blink then off | blinking followed by off |

## Timers

A timer temporarily overrides the normal LED state. When it ends, MagSafe Dark recalculates the state that should be active at that moment instead of restoring a potentially outdated value.

```bash
magsafe-dark for 900 off
magsafe-dark timer-status
magsafe-dark cancel-timer
```

## Weekly schedule

Open **Configure Schedule…** from the app menu. Each interval can contain one or more weekdays, a start time, an end time, and an LED mode. Intervals may cross midnight.

The default disabled template is:

```text
Every day  08:00–23:00  System
Every day  23:00–08:00  Off
```

When the schedule is enabled, its current mode is applied immediately. A user timer or active Codex indication is allowed to finish first. Manual selection while a schedule is active remains in effect until the next schedule boundary.

Power-source changes are observed through IOKit. When external power appears and the schedule is enabled, the current schedule is applied immediately and repeated after a short delay as a safeguard.

## Codex CLI indication

MagSafe Dark can show Codex CLI state through the MagSafe LED:

- working;
- success;
- error.

Use Codex through the wrapper:

```bash
codex-led
codex-led exec "Fix the failing tests"
```

Several Codex tasks may run at the same time. The working indication remains active while at least one task is running.

## Priority order

```text
1. User timer
2. Active Codex indication
3. Manual override until the next schedule boundary
4. Current schedule interval
5. Persistent manual mode
6. Normal macOS control
```

## Command-line use

Direct control:

```bash
magsafe-dark off
magsafe-dark system
magsafe-dark green
magsafe-dark orange
magsafe-dark flash
magsafe-dark blink-slow
magsafe-dark blink-fast
magsafe-dark blink-off
```

Schedule:

```bash
magsafe-dark schedule edit
magsafe-dark schedule status
magsafe-dark schedule enable
magsafe-dark schedule disable
magsafe-dark schedule next
```

Run another command with LED indication:

```bash
magsafe-dark run -- make test
magsafe-dark run --working blink-slow -- npm run build
magsafe-dark run --success green --error blink-fast -- ./deploy.sh
```

The wrapped command keeps its original exit code.

## Diagnostics

```bash
magsafe-dark status
magsafe-dark settings
magsafe-dark state
magsafe-dark diagnostics
magsafe-dark log-path
```

## Troubleshooting

Check compatibility and the background service:

```bash
magsafe-dark probe
/usr/local/libexec/magsafe-led-client ping
/usr/local/libexec/magsafe-led-client status
```

Expected ping result:

```text
pong
```

An active timer or Codex indication has higher priority than the schedule. Run `magsafe-dark schedule status` when the schedule does not appear to apply.

## Uninstall

```bash
zsh ./uninstall.sh
```

This returns the LED to normal macOS control and removes MagSafe Dark, its background services, schedule, settings, and logs.

## Privacy and security

MagSafe Dark works locally. The privileged background service accepts only a fixed set of LED commands and does not execute arbitrary shell commands. Normal app and CLI use does not require `sudo` after installation.

## License

[MIT](LICENSE)
