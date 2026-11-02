# Dotfiles

Personal macOS and Ubuntu setup managed with **GNU Stow** for configuration
symlinks and **Homebrew Bundle** for packages. Scripts install the tools and
configs for each host, then print the remaining sign-ins and manual setup.

## Table of contents

- [Quick start](#quick-start)
- [Hosts](#hosts)
- [Common commands](#common-commands)
- [Repository layout](#repository-layout)
- [Documentation](#documentation)

## Quick start

Have Git and curl available before starting; Ubuntu also needs
`build-essential`. On macOS, bootstrap requests Xcode Command Line Tools if
missing; finish that installation and rerun bootstrap. Bootstrap may ask for
administrator access.

```sh
git clone "https://github.com/Tahseenm/dotfiles" ~/.dotfiles
cd ~/.dotfiles

# Install Homebrew and the provisioning tools.
./bootstrap.sh

# Choose your host from the table below.
HOST=macbook ./install.sh

# Generate a personal SSH key and register it with GitHub.
./github-ssh.sh --title "Macbook Pro"
```

For `macbook`, sign into the App Store before running install, including dry
runs. After installation, complete the printed manual steps, also saved to
`manual-steps.md` (git-ignored and overwritten on each install). On either Mac,
optionally apply the curated preference tweaks with `bash macos-defaults.sh`
(preview with `--dry-run`, then `--apply`; see
[macOS defaults](docs/usage.md#macos-defaultssh)). Open a new login shell, then
run `./doctor.sh` to check for drift.

For existing configurations, read
[Adopting existing files](docs/usage.md#adopting-existing-files) before installing.

## Hosts

Set `HOST` to select the manifest that defines packages and configs.

| HOST | Machine | Manifest |
| --- | --- | --- |
| `macbook` | Main macOS workstation | [macbook.toml](hosts/macbook.toml) |
| `mac-mini` | Headless Mac mini with a virtual display | [mac-mini.toml](hosts/mac-mini.toml) |
| `linux-pc` | Headless Ubuntu mini PC | [linux-pc.toml](hosts/linux-pc.toml) |

## Common commands

Run from `~/.dotfiles`, replacing `mac-mini` with your host:

```sh
HOST=mac-mini ./install.sh --dry-run  # Preview changes
HOST=mac-mini ./install.sh            # Install or reapply configuration
./doctor.sh                           # Report package and symlink drift
bash macos-defaults.sh --dry-run      # Preview macOS preference tweaks (macOS only)
bash macos-defaults.sh --apply        # Back up and apply them (macOS only)
```

Install preserves existing runtimes and coding agents on repeat runs. Doctor
checks every Brewfile and host manifest; see [script behavior](docs/usage.md#scripts)
for details.

## Repository layout

- [hosts/](hosts/) — per-host manifests selecting a Brewfile and Stow packages.
- [brew/](brew/) — shared packages and host-specific Brewfiles.
- [stow/](stow/) — shell, Git, terminal, and tool configuration packages.
- [pnpm-global/](pnpm-global/) — global pnpm package declarations and installer.
- [docs/](docs/) — detailed usage and development guidance.

## Documentation

- [Usage guide](docs/usage.md) — script behavior, package and runtime policies,
  existing-file adoption, and operational caveats.
- [Development guide](docs/development.md) — verification commands and manual
  test checklists for macOS, Ubuntu, repeat runs, and removing symlinks.
