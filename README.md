# MagSafe Dark

A lightweight macOS menu bar utility for controlling the MagSafe connector LED on Apple Silicon MacBooks.

> [!WARNING]
> MagSafe Dark writes to the undocumented Apple SMC key `ACLC`. Use it at your own risk. A macOS or firmware update may change or remove this behavior.

## Features

- Disable the MagSafe LED.
- Restore normal system-controlled behavior.
- Dynamic menu action based on the current LED state.
- Dynamic menu bar icon that follows the actual SMC LED mode.
- Optional monochrome icon or colored bulb indication.
- Force green or orange LED modes.
- Automation states for builds, scripts and AI coding agents.
- Codex CLI wrapper with working, success and error indication.
- No repeated password prompts after installation.

## Compatibility

- macOS 13 or newer.
- Apple Silicon MacBook with MagSafe 3.
- Tested on MacBook Pro M5.
- Reports for other models are welcome.

## Install from GitHub Releases

Download the latest installer from the [Releases page](https://github.com/bulava92/magsafe-dark/releases/latest):

- `MagSafeDark-1.1.0-unsigned.pkg`

Open the downloaded package and follow the installer steps. It installs:

- `/Applications/MagSafe Dark.app`
- `/usr/local/libexec/magsafe-led-helper`
- `/usr/local/bin/magsafe-dark`
- `/usr/local/bin/codex-led`
- `/etc/sudoers.d/magsafe-dark`

The current package is unsigned. macOS may block it because it is not signed and notarized with an Apple Developer ID certificate.

When that happens:

1. Try to open the package once.
2. Open **System Settings → Privacy & Security**.
3. Click **Open Anyway** for MagSafe Dark.

Only install packages published in this repository's Releases section.

## Install from source

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

The installer requests an administrator password once and installs the same components as the package.

## Update

For a package installation, download and open the newer `.pkg` from [GitHub Releases](https://github.com/bulava92/magsafe-dark/releases/latest). It replaces the existing application and command-line components.

For a source installation:

```bash
cd ~/Projects/magsafe-dark
git pull
./install.sh
```

## Build the application

```bash
zsh ./build.sh
```

The application is created at:

```text
build/MagSafe Dark.app
```

## Build an unsigned installer package

```bash
zsh ./build-pkg.sh
```

The default output is:

```text
build/MagSafeDark-1.1.0-unsigned.pkg
```

Specify another package version as the first argument:

```bash
zsh ./build-pkg.sh 1.2.0
```

Test the package locally:

```bash
sudo installer \
  -pkg build/MagSafeDark-1.1.0-unsigned.pkg \
  -target /
```

Inspect its payload:

```bash
pkgutil --payload-files build/MagSafeDark-1.1.0-unsigned.pkg
```

The generated package is unsigned. For public distribution without Gatekeeper warnings, the application and package must be signed with Apple Developer ID certificates and notarized by Apple.

## Menu bar controls

The main action changes dynamically:

- LED active: **Turn LED off**
- LED off: **Restore system mode**

The menu bar icon is refreshed every second, so changes made by `codex-led`, shell scripts or other processes are reflected without reopening the menu.

The **Icon appearance** submenu provides:

- **Monochrome** — uses the standard macOS template icon and adapts to light or dark menu bars.
- **Color the bulb using the LED color** — only the bulb is green or orange; its outline and socket remain in the normal system menu bar color.

The selected icon appearance is stored in `UserDefaults` and persists after restarting the app.

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

The script removes the application, helper, command-line tools and sudoers rule.

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
