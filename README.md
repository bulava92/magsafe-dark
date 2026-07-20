# MagSafe Dark

[Русская версия](README_RU.md)

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

- Turn the MagSafe LED off.
- Return the LED to normal macOS control.
- Show green, orange, a single indication, or one of several blinking effects.
- Start a temporary mode for a selected duration.
- Create a weekly schedule for different times and days.
- Use separate LED modes for Codex work, success, and error states.
- Start automatically when you sign in.
- View diagnostics and logs from the app menu.

## Installation

Version 1.4.0 is currently installed from source:

```bash
git clone https://github.com/bulava92/magsafe-dark.git
cd magsafe-dark
git checkout develop-1.4.0
zsh ./scripts/check-release.sh
zsh ./install.sh
```

The installer asks for the administrator password once. After installation, normal app and command-line use does not require `sudo`.

The app is installed as:

```text
/Applications/MagSafe Dark.app
```

## Using the menu-bar app

Open **MagSafe Dark** from Applications. Its icon appears in the macOS menu bar.

From the menu you can:

- choose an LED mode;
- start or cancel a timer;
- configure the weekly schedule;
- configure Codex indication;
- enable launch at login;
- change the menu-bar icon style;
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

A timer temporarily overrides the normal LED state.

Example: turn the LED off for 30 minutes. When the timer ends, MagSafe Dark recalculates what should be active at that moment. It does not blindly restore an outdated previous value.

This matters when a schedule changes during the timer. For example:

```text
22:50  Green timer starts for 30 minutes
23:00  Night schedule becomes active
23:20  Timer ends
23:20  Night schedule is applied
```

## Weekly schedule

Open **Configure Schedule…** from the app menu.

For each interval you can choose:

- one or more days of the week;
- start time;
- end time;
- LED mode.

Intervals may cross midnight. For example, `23:00–08:00` starts in the evening and ends the next morning.

The default template is:

```text
Every day  08:00–23:00  System
Every day  23:00–08:00  Off
```

The template is disabled until you enable the schedule and save it.

You can also choose what happens outside configured intervals:

- use normal macOS control;
- keep the LED off;
- use the last persistent manual mode.

When the schedule is enabled, its current mode is applied immediately. An already active timer or Codex indication is allowed to finish first.

### Manual control while a schedule is enabled

Choosing a mode manually creates a temporary override until the next schedule boundary.

Example:

```text
21:00  Manual Green selected
23:00  Next schedule interval starts
23:00  Schedule regains control
```

When the schedule is disabled, a manually selected mode remains active until changed again.

## Codex CLI indication

MagSafe Dark can use the MagSafe LED to show Codex CLI state:

- working;
- success;
- error.

Each state has its own LED mode. Success and error can also have separate durations and notifications.

Use Codex through the wrapper:

```bash
codex-led
codex-led exec "Fix the failing tests"
```

Several Codex tasks may run at the same time. The working indication remains active while at least one task is still running. Final indication is shown after the last active task finishes.

## How schedule, Codex, timers, and manual control interact

MagSafe Dark uses this priority order:

```text
1. User timer
2. Active Codex indication
3. Manual override until the next schedule boundary
4. Current schedule interval
5. Persistent manual mode
6. Normal macOS control
```

Examples:

- A user timer is not interrupted by Codex.
- Codex temporarily overrides the schedule.
- After Codex finishes, the current schedule is recalculated.
- A manual selection during an active schedule lasts until the next schedule change.
- Enabling the schedule clears an old manual schedule override and applies the current interval immediately.

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
```

Run another command with LED indication:

```bash
magsafe-dark run -- make test
magsafe-dark run --working blink-slow -- npm run build
magsafe-dark run --success green --error blink-fast -- ./deploy.sh
```

The wrapped command keeps its original exit code.

## Diagnostics

Useful commands:

```bash
magsafe-dark status
magsafe-dark settings
magsafe-dark state
magsafe-dark diagnostics
magsafe-dark log-path
```

The app menu also provides access to diagnostics and logs.

## Troubleshooting

### The LED does not change

Check compatibility:

```bash
magsafe-dark probe
```

Check the background service:

```bash
/usr/local/libexec/magsafe-led-client ping
/usr/local/libexec/magsafe-led-client status
```

Expected ping result:

```text
pong
```

### The schedule does not apply

Check its state:

```bash
magsafe-dark schedule status
```

An active timer or Codex indication has higher priority than the schedule. The schedule will apply when that temporary state finishes.

### The schedule editor does not open

Run it from Terminal to see the error directly:

```bash
magsafe-dark schedule edit
```

## Uninstall

From the project folder:

```bash
zsh ./uninstall.sh
```

This returns the LED to normal macOS control and removes MagSafe Dark, its background services, schedule, settings, and logs.

## Privacy and security

MagSafe Dark works locally. The privileged background service accepts only a fixed set of LED commands and does not execute arbitrary shell commands.

Normal app and CLI use does not require `sudo` after installation.

## License

MIT
