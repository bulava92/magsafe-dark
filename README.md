# MagSafe Dark

A lightweight macOS menu bar utility for disabling the MagSafe connector LED on Apple Silicon MacBooks.

> [!WARNING]
> MagSafe Dark writes to the undocumented Apple SMC key `ACLC`. Use it at your own risk. A macOS or firmware update may change or remove this behavior.

## Features

- Disable the MagSafe LED.
- Restore normal system-controlled behavior.
- Dynamic menu action based on the current LED state.
- Force green or orange LED modes for testing.
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

The installer requests an administrator password once. It builds the app, installs a root-owned helper, adds a narrowly scoped sudoers rule, and opens the menu bar app.

## Update

```bash
cd magsafe-dark
git pull
./install.sh
```

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

The helper and application are installed as `root:wheel`, preventing modification by a standard user.

## License

MIT
