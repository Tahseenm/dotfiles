# Development guide

[Back to README](../README.md)

Use these checks when changing provisioning scripts or configuration. See the
[usage guide](usage.md) for script behavior and package policies.

## Table of contents

- [Manual test checklist](#manual-test-checklist)
  - [Fresh macOS](#fresh-macos)
  - [Fresh Ubuntu](#fresh-ubuntu)
  - [Repeat runs](#repeat-runs)
  - [Removing symlinks](#removing-symlinks)
- [Verification](#verification)

## Manual test checklist

### Fresh macOS

- [ ] Clone to `~/.dotfiles` and run `./bootstrap.sh`; re-run it and confirm it
      is a no-op.
- [ ] `HOST=macbook ./install.sh` (or `mac-mini`) completes without sudo
      prompts and prints manual steps.
- [ ] Open a new login shell: prompt renders, `cd` works (zoxide), `l`/`tree`
      work (eza), history is under `~/.local/state/zsh`, no errors.
- [ ] `brew`, `node`, `pnpm`, and `bun` resolve in a new login shell and
      `node --version`, `pnpm --version`, and `bun --version` succeed.
- [ ] `./doctor.sh` reports no drift.
- [ ] `./macos-defaults.sh --dry-run` prints the planned commands and
      changes nothing.
- [ ] `./macos-defaults.sh --apply` writes the preferences and creates a
      timestamped backup directory; after logging out and back in,
      `./macos-defaults.sh --check` reports no differences and exits 0.
- [ ] On a machine that has not applied the profile, `--check` lists the
      differences and exits non-zero.
- [ ] Run the printed manual steps (gh, Tailscale, GUI app permissions). On the
      macbook the GUI app is installed; on the mac mini the CLI daemon is.
- [ ] RustDesk is installed. On the mac mini, grant Screen Recording,
      Accessibility, and Input Monitoring, set a permanent password, confirm the
      service is running, then connect unattended.

### Fresh Ubuntu

- [ ] Install prerequisites (`curl`, `git`, `build-essential`), clone, run
      `./bootstrap.sh` (installs zsh with `apt-get`, then Homebrew on Linux).
- [ ] `HOST=linux-pc ./install.sh` completes; no casks are attempted.
- [ ] Set zsh as the login shell: `chsh -s "$(command -v zsh)"`, then log out
      and back in.
- [ ] New login shell behaves as above (brew path comes from `.zprofile`).
- [ ] `node --version`, `pnpm --version`, and `bun --version` succeed.
- [ ] Run the printed manual steps (gh, Tailscale CLI daemon).
- [ ] Install the downloaded RustDesk `.deb` with the printed `sudo apt install`
      step, set a permanent password (`sudo rustdesk --password`; the CLI needs
      root), and connect unattended (including at the login screen, per the
      Wayland build).
- [ ] `./doctor.sh` reports no drift.

### Repeat runs

- [ ] Run `HOST=<host> ./install.sh` twice; the second run changes nothing and
      exits 0.
- [ ] `HOST=<host> ./install.sh --dry-run` reports the same state.
- [ ] Runtime versions and the fnm default stay unchanged on repeat runs;
      no runtime downloads occur when all three tools are installed.
- [ ] On a fresh home, `--dry-run` creates no runtime directories and does
      not download installers. Real installation leaves shell configs untouched.

### Removing symlinks

- [ ] `stow --delete --target="$HOME" --dir="$PWD/stow" <package>` removes only
      that package's symlinks and leaves real files elsewhere intact.
- [ ] Re-running `HOST=<host> ./install.sh` restores them.

## Verification

Run from the repository root with Homebrew, GNU Stow, dasel, and ShellCheck
available. Stow simulations and Brewfile checks report against the current
machine, so review any host-specific differences.

```sh
bash -n bootstrap.sh install.sh doctor.sh github-ssh.sh macos-defaults.sh
shellcheck bootstrap.sh install.sh doctor.sh github-ssh.sh macos-defaults.sh
for h in macbook mac-mini linux-pc; do
  while read -r p; do
    stow --simulate --restow --no-folding --target="$HOME" --dir="$PWD/stow" "$p"
  done < <(dasel -i toml -o json 'stow.packages' < "hosts/$h.toml" | tr -d '[]"' | tr ',' '\n' | grep -v '^$')
done
for f in brew/Brewfile.*; do brew bundle check --no-upgrade --file="$f"; done
```
