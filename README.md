# MagSafe Dark

[Русская версия](README_RU.md)

<p align="center">
  <a href="https://boosty.to/smd.monster/donate">
    <img src="https://img.shields.io/badge/Support_the_project-Boosty-f15f2c?style=for-the-badge" alt="Support the project on Boosty">
  </a>
</p>

MagSafe Dark is a macOS menu bar app for controlling the LED on a MagSafe connector.

> The app uses the undocumented Apple SMC key `ACLC`. A macOS or firmware update may change or completely disable this behavior.

## Requirements

- macOS 13 or newer;
- Apple Silicon MacBook with MagSafe 3.

Check support after installation:

```bash
magsafe-dark probe
```

Expected result:

```text
supported
```

## Features

- turn the MagSafe LED off or restore normal macOS control;
- green, orange, and blinking modes;
- temporary modes;
- weekly schedules;
- Codex CLI working, success, and error indication;
- automatic schedule application after power-source changes;
- optional battery, charging, and charge-completion information in the menu bar;
- diagnostics, logs, CLI, and update checks;
- `.pkg` building, Developer ID signing, and notarization.

## Installation

### Installer package

```bash
zsh ./scripts/check-release.sh --package
open build
```

Build a local package directly:

```bash
zsh ./build-pkg.sh
open build
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

macOS asks for the administrator password once during installation. Normal app and CLI use does not require `sudo` afterwards.

The app is installed at `/Applications/MagSafe Dark.app`.

## LED modes

| Mode | Action |
|---|---|
| System | macOS controls the LED normally |
| Off | LED remains off |
| Green | solid green |
| Orange | solid orange |
| Single indication | one short indication |
| Slow blink | slow orange blinking |
| Fast blink | fast orange blinking |
| Blink then off | blinking followed by off |

Keyboard shortcuts while the menu is open:

- `⌘⇧0` — switch between Off and System;
- `⌘⇧G` — Green;
- `⌘⇧O` — Orange;
- `⌘Q` — Quit.

## Power and charging

The app subscribes to native IOKit power-source notifications. Connecting or disconnecting the charger updates the state immediately.

When external power is connected and the schedule is enabled, MagSafe Dark runs `schedule apply` immediately and repeats it about three seconds later. The delayed pass protects against cases where the MagSafe or power state has not fully stabilized yet.

The menu bar can optionally show:

- battery percentage;
- active charging state;
- estimated charge completion time.

These options only affect status display and do not change LED behavior.

## Timers

A timer temporarily overrides the normal LED state. When it ends, the app recalculates the mode that should be active at that moment instead of restoring a stale previous value.

For example, when a schedule boundary occurs during a timer, the new schedule interval is applied after the timer finishes.

## Weekly schedule

Each interval defines days, start time, end time, and an LED mode. Intervals may cross midnight.

Default template:

```text
Every day  08:00–23:00  System
Every day  23:00–08:00  Off
```

The template remains inactive until the schedule is enabled and saved.

Outside configured intervals, the app can use:

- normal macOS control;
- LED off;
- the last persistent manual mode.

### Manual control while a schedule is active

Selecting a mode manually while the schedule is enabled creates an override that lasts until the next schedule boundary. The schedule then regains control.

When the schedule is disabled, a manually selected mode is persistent until the user changes it again.

## Codex CLI indication

MagSafe Dark can represent:

- working;
- successful completion;
- error.

Each state has a configurable LED mode. Success and error can also use separate durations and notifications.

Run Codex through the wrapper:

```bash
codex-led
codex-led exec "Fix the failing tests"
```

When several tasks run simultaneously, the working indication remains active until the final task exits.

## Mode priority

```text
1. User timer
2. Active Codex indication
3. Manual override until the next schedule boundary
4. Current schedule interval
5. Persistent manual mode
6. Normal macOS control
```

After a temporary state finishes, the app recalculates the current desired mode. Therefore:

- a user timer is not interrupted by Codex;
- Codex temporarily overrides the schedule;
- the current schedule interval is restored after Codex;
- a manual selection during an active schedule lasts only until the next boundary;
- connecting power reapplies the current schedule.

## Menu bar status

The menu bar may show the current LED mode, remaining timer duration, battery percentage, charging state, and charge-completion estimate. Icon style and status text options are independent from LED-control logic.

## CLI

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

Timers:

```bash
magsafe-dark for 900 off
magsafe-dark timer-status
magsafe-dark cancel-timer
```

Schedule:

```bash
magsafe-dark schedule edit
magsafe-dark schedule status
magsafe-dark schedule enable
magsafe-dark schedule disable
magsafe-dark schedule next
magsafe-dark schedule apply
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

### The LED does not change

```bash
magsafe-dark probe
/usr/local/libexec/magsafe-led-client ping
/usr/local/libexec/magsafe-led-client status
```

The expected ping response is `pong`.

### The schedule does not apply

```bash
magsafe-dark schedule status
magsafe-dark schedule apply
```

A timer or active Codex indication has higher priority. The schedule applies after the temporary state finishes.

### The schedule editor does not open

```bash
magsafe-dark schedule edit
```

Running it from Terminal exposes the error message directly.

## Signing and notarization

`build-pkg.sh` creates an unsigned installer package. `scripts/sign-and-notarize.sh` signs the app and package with Developer ID certificates, submits the package to Apple notarization, and staples the ticket.

Certificate identities and the notarization profile are supplied through environment variables; see the script and repository signing documentation for details.

## Limitations and security

MagSafe Dark works locally. The privileged background service accepts only a fixed set of LED commands and does not execute arbitrary shell commands.

`ACLC` is not a public Apple API. Compatibility may change after a macOS update, firmware update, or a new MacBook generation even when installation is otherwise correct.

## Uninstall

```bash
zsh ./uninstall.sh
```

The script restores normal macOS LED control and removes the app, services, schedule, settings, and logs.

## License

[MIT](LICENSE)
