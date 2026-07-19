# MagSafe Dark

A lightweight macOS menu bar utility for controlling the MagSafe connector LED on Apple Silicon MacBooks.

> [!WARNING]
> MagSafe Dark writes to the undocumented Apple SMC key `ACLC`. Use it at your own risk. A macOS or firmware update may change or remove this behavior.

## Features

- Disable the MagSafe LED.
- Restore normal system-controlled behavior.
- Dynamic menu action based on the current LED state.
- Force green or orange LED modes.
- Automation states for builds, scripts and AI coding agents.
- Codex CLI wrapper with working, success and error indication.
- No repeated password prompts after installation.

## Compatibility

- macOS 13 or newer.
- Apple Silicon MacBook with MagSafe 3.
- Tested on MacBook Pro M5.
- Reports for other models are welcome.

## Install

Install Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

Then clone and install:

```bash
git clone https://github.com/bulava92/magsafe-dark.git
cd magsafe-dark
chmod +x build.sh install.sh uninstall.sh
./install.sh
```

The installer requests an administrator password once. It installs:

- `/Applications/MagSafeDark.app`
- `/usr/local/libexec/magsafe-led-helper`
- `/usr/local/bin/magsafe-dark`
- `/usr/local/bin/codex-led`

## Update

```bash
cd magsafe-dark
git pull
./install.sh
```

## Menu bar controls

The main action changes dynamically:

- LED active: **Turn LED off**
- LED off: **Restore system mode**

The **Automation state** submenu provides:

- Working — orange
- Success — green, then system mode
- Error — orange, then system mode
- Idle — system mode

## Command-line automation

```bash
magsafe-dark working
magsafe-dark success
magsafe-dark error
magsafe-dark idle
```

Direct LED commands are also available:

```bash
magsafe-dark off
magsafe-dark system
magsafe-dark green
magsafe-dark orange
magsafe-dark status
```

By default, `success` and `error` return to system mode after 5 seconds. Override the delay per command:

```bash
MAGSAFE_DARK_SUCCESS_SECONDS=10 magsafe-dark success
MAGSAFE_DARK_ERROR_SECONDS=15 magsafe-dark error
```

Starting a new state cancels a pending automatic reset, so an old `success` timer cannot interrupt a newer `working` state.

## Codex CLI

Run Codex through the included wrapper:

```bash
codex-led
```

All Codex arguments are passed through unchanged:

```bash
codex-led exec "Fix the failing tests"
codex-led --help
```

Behavior:

1. Orange while the Codex process is running.
2. Green for 5 seconds when Codex exits successfully.
3. Orange for 5 seconds when Codex exits with an error.
4. System-controlled mode afterward.

The wrapper detects `codex` from `PATH`. A custom executable can be supplied:

```bash
CODEX_BIN="$HOME/.local/bin/codex" codex-led
```

This integration is reliable for Codex CLI. The ChatGPT desktop app and the Codex VS Code extension do not currently expose a stable public task-state interface to this utility, so merely detecting that those applications are open would not reliably indicate whether Codex is actively working.

## Other integrations

Any shell command can use the LED as a status indicator:

```bash
magsafe-dark working
if npm test; then
  magsafe-dark success
else
  magsafe-dark error
fi
```

Another compact pattern:

```bash
magsafe-dark working
make build && magsafe-dark success || magsafe-dark error
```

This can be used with builds, tests, backups, deployments, SSH jobs and rendering tasks.

## Uninstall

```bash
./uninstall.sh
```

## LED modes

The helper reads and writes the SMC key `ACLC`:

| Value | Mode |
|---:|---|
| `0` | System controlled |
| `1` | Off |
| `3` | Green |
| `4` | Orange |

Arbitrary brightness control is not known to be supported.

## Security

The privileged helper is installed at `/usr/local/libexec/magsafe-led-helper`. The sudoers rule permits only these exact commands without a password:

- `off`
- `system`
- `green`
- `orange`
- `status`

The helper, command wrappers and application are installed as `root:wheel`, preventing modification by a standard user.

## License

MIT
