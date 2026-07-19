# MagSafe Dark

A lightweight macOS menu bar utility for controlling the MagSafe connector LED on Apple Silicon MacBooks.

> [!WARNING]
> MagSafe Dark writes to the undocumented Apple SMC key `ACLC`. Use it at your own risk. A macOS or firmware update may change or remove this behavior.

## Features

- Turn the MagSafe LED off or restore normal system control.
- Force green or orange indication.
- Use single-flash, slow-blink, fast-blink and blink-then-off effects.
- Start automatically at login.
- Optionally restore the last selected LED mode after launch.
- Temporarily apply a mode using menu timers or the CLI.
- Show the current raw LED mode and Mac compatibility diagnostics.
- Use menu keyboard shortcuts for common actions.
- Configure Codex completion duration and notifications.
- Wrap any shell command with working, success and error LED states.
- Check the latest GitHub Release from the application menu.
- Build and publish unsigned installer packages automatically with GitHub Actions.

## Compatibility

- macOS 13 or newer.
- Apple Silicon MacBook with MagSafe 3.
- Tested on MacBook Pro M5.
- Reports for other models are welcome.

## Install from GitHub Releases

Download the latest installer from the [Releases page](https://github.com/bulava92/magsafe-dark/releases/latest) and open the `.pkg` file.

The package installs:

- `/Applications/MagSafe Dark.app`
- `/usr/local/libexec/magsafe-led-helper`
- `/usr/local/bin/magsafe-dark`
- `/usr/local/bin/codex-led`
- `/etc/sudoers.d/magsafe-dark`

The current package is unsigned. If macOS blocks it, try opening it once and then use **System Settings → Privacy & Security → Open Anyway**.

## Install from source

```bash
git clone https://github.com/bulava92/magsafe-dark.git
cd magsafe-dark
chmod +x build.sh install.sh uninstall.sh
./install.sh
```

Install Xcode Command Line Tools first when required:

```bash
xcode-select --install
```

## Update

Package installation: download and open the newer `.pkg` from GitHub Releases.

Source installation:

```bash
cd ~/Projects/magsafe-dark
git pull
./install.sh
```

## Menu bar controls

The menu displays the current SMC mode and includes:

- Off and system-controlled modes.
- Green and orange forced colors.
- Single indication and three blinking effects.
- Temporary 15-minute and one-hour timers.
- Launch-at-login control using `SMAppService`.
- Optional restoration of the last selected mode.
- Monochrome or LED-colored menu bar icon.
- Codex duration presets and notification control.
- Diagnostics and a link to the latest release.

Keyboard shortcuts while the menu is open:

- `⌘⇧0` — toggle off/system mode.
- `⌘⇧G` — green.
- `⌘⇧O` — orange.
- `⌘Q` — quit.

## Command-line automation

Task states:

```bash
magsafe-dark working
magsafe-dark success
magsafe-dark error
magsafe-dark idle
```

Direct modes:

```bash
magsafe-dark off
magsafe-dark system
magsafe-dark green
magsafe-dark orange
magsafe-dark flash
magsafe-dark blink-slow
magsafe-dark blink-fast
magsafe-dark blink-off
magsafe-dark status
```

Temporary mode:

```bash
magsafe-dark for 900 off
magsafe-dark for 3600 orange
```

Run any command with automatic LED status handling:

```bash
magsafe-dark run -- make test
magsafe-dark run --working blink-slow -- npm run build
magsafe-dark run --success green --error blink-fast --delay 10 -- ./deploy.sh
```

The command exit code is preserved. A successful command uses the success mode; a failed command uses the error mode; then system mode is restored after the selected delay.

Environment overrides remain available:

```bash
MAGSAFE_DARK_SUCCESS_SECONDS=10 magsafe-dark success
MAGSAFE_DARK_ERROR_SECONDS=15 magsafe-dark error
MAGSAFE_DARK_NOTIFICATIONS=0 magsafe-dark success
```

Without environment overrides, the CLI reads duration and notification preferences stored by the menu bar application.

## Codex CLI

Run Codex through the included wrapper:

```bash
codex-led
codex-led exec "Fix the failing tests"
```

Behavior:

1. Orange while Codex is running.
2. Green after successful completion.
3. Orange after an error.
4. Optional macOS notification.
5. System-controlled mode after the configured delay.

The ChatGPT desktop app and Codex editor extensions do not currently expose a stable task-state interface to this utility. The wrapper therefore targets Codex CLI.

## Diagnostics

The **Diagnostics** menu shows:

- Mac model.
- Whether the privileged helper is installed.
- Current raw `ACLC` value or the read error.
- Installed application path.

## Build

Build the application:

```bash
zsh ./build.sh
```

Build an unsigned installer package:

```bash
zsh ./build-pkg.sh 1.2.0
```

Output:

```text
build/MagSafeDark-1.2.0-unsigned.pkg
```

Test it:

```bash
sudo installer -pkg build/MagSafeDark-1.2.0-unsigned.pkg -target /
```

## Automated Releases

Pushing a version tag triggers `.github/workflows/release.yml`:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow:

1. Builds on a macOS runner.
2. Creates the unsigned `.pkg`.
3. Generates a SHA-256 checksum.
4. Creates release notes.
5. Attaches the package and checksum to the GitHub Release.

The workflow can also be run manually from the Actions tab without publishing a Release.

## LED modes

| Value | Command | Mode |
|---:|---|---|
| `0` | `system` | System controlled |
| `1` | `off` | Off |
| `3` | `green` | Green |
| `4` | `orange` | Orange |
| `5` | `flash` | Single indication |
| `6` | `blink-slow` | Slow orange blinking |
| `7` | `blink-fast` | Fast orange blinking |
| `19` | `blink-off` | Orange blinking followed by off |

Arbitrary RGB color and brightness control are not known to be supported.

## Security

The helper and application are installed as `root:wheel`. The sudoers rule permits only the explicitly listed helper commands and does not grant unrestricted passwordless sudo access.

## Uninstall

```bash
./uninstall.sh
```

## License

MIT