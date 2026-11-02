# Usage guide

[Back to README](../README.md)

Reference for provisioning, package management, and existing configurations.
Run the commands below from `~/.dotfiles`. For initial setup, start with the
[quick start](../README.md#quick-start).

## Table of contents

- [Scripts](#scripts)
  - [Bootstrap](#bootstrapsh)
  - [Install](#installsh)
  - [Doctor](#doctorsh)
  - [GitHub SSH key](#github-sshsh)
  - [macOS defaults](#macos-defaultssh)
- [Per-host values](#per-host-values)
- [Packages](#packages)
  - [Language runtimes](#language-runtimes)
- [Adopting existing files](#adopting-existing-files)
- [Caveats](#caveats)

## Scripts

### `bootstrap.sh`

Takes a bare machine to the point where `install.sh` can run. Safe to re-run.

- macOS: requires Xcode Command Line Tools (requests the install if missing),
  then installs Homebrew and `git stow dasel mas`.
- Linux: installs zsh with the distro package manager (`apt-get`), then
  Homebrew on Linux, then `git stow dasel`. zsh is installed here rather than
  from a Brewfile so it lands in `/etc/shells` and `chsh` accepts it.
- Installing Homebrew requires administrator access. On a fresh machine
  `bootstrap.sh` acquires sudo first (prompting for your password once, unless
  credentials are already cached), because Homebrew's installer runs
  non-interactively and cannot prompt for it itself.
- On a **headless** Mac, `xcode-select --install` may need to complete out of
  band; re-run `bootstrap.sh` once it finishes.

### `install.sh`

```sh
HOST=<host> ./install.sh            # apply
HOST=<host> ./install.sh --dry-run  # show what would happen
```

- Fails loudly (listing valid hosts) if `HOST` is missing or unknown.
- For `HOST=macbook`, asks whether you have signed into the App Store before
  provisioning (including `--dry-run`); only `y` or `yes`, ignoring case, proceeds.
- Locates Homebrew itself (Apple Silicon or Linux prefix) when `brew`
  is not yet on `PATH`, so it works in a fresh shell right after
  `bootstrap.sh`.
- Reads `brew.file` and `stow.packages` from `hosts/<HOST>.toml` with `dasel`.
- Installs `brew/Brewfile.base` first, then the host Brewfile, each with
  `brew bundle install --file=<file> --no-upgrade`.
- Runs `stow --restow --no-folding --target="$HOME" --dir=stow <package>` per
  package. `--no-folding` links individual files and keeps real directories,
  so tools that write runtime state (for example `micro`'s `buffers/history`)
  do not write back into the repo.
- `--dry-run` runs Stow with `-n -v` and reports each Brewfile's status with a
  read-only `brew bundle check --no-upgrade` instead of invoking
  `brew bundle install --dry-run`. It prints planned runtime actions without
  initializing fnm, downloading installers, or changing runtime versions.
- Installs missing Node, pnpm, and Bun after Stow (see
  [Language runtimes](#language-runtimes)). Existing versions are preserved on
  repeat runs; installation failures stop the script.
- Installs missing global pnpm packages declared in `pnpm-global/package.json`.
  Add package names and version specifications under `dependencies`, then rerun
  `install.sh`. Existing packages are preserved without version checks or
  upgrades; removing an entry does not uninstall it. Dry runs show the entries.
- Installs missing Codex, Claude Code, and OpenCode 2 after runtimes using their
  official install scripts. Existing commands are preserved, including OpenCode
  1; reruns do not upgrade them. Sign in using the printed manual steps.
- On Linux, resolves the current RustDesk Wayland unattended preview from the
  nightly release and downloads the `.deb` into `~/Downloads`, publishing it only
  once the transfer completes (an interrupted run leaves no partial package
  behind); installing it needs `sudo`, so it stays a printed manual step.
- Never prompts for `sudo`.
- Prints the manual steps and also writes them to `manual-steps.md` in the
  repo root as a Markdown `- [ ]` checklist (git-ignored, one file per
  machine, overwritten on each real run). Not written under `--dry-run`.

### `doctor.sh`

Read-only; changes nothing. Reports:

- `brew bundle check --no-upgrade` for every Brewfile.
- Every expected Stow symlink, for every package on every host manifest. For
  each tracked file under `stow/<package>/`, the file at `$HOME/<rel>` must be
  a symlink pointing back into the repo. This catches deleted or misdirected
  links (and an empty `$HOME`), which a conflict-free `stow --simulate` does
  not.
- `git status` of the repository.

### `github-ssh.sh`

```sh
./github-ssh.sh --title <title>   # generate and register a personal SSH key
./github-ssh.sh --dry-run         # show what would happen
```

Run after `install.sh` (which installs `gh`). It targets your **personal**
GitHub account only.

- Requires `gh`. Checks only the active account's authentication. If you are
  not signed in, it runs `gh auth login --hostname github.com --git-protocol
  ssh --web --scopes admin:public_key`.
- Before generating a key or changing local configuration, checks the selected
  account's SSH-key write scope and requests `admin:public_key` with
  `gh auth refresh` if missing. Uses a browser login or classic token with
  verifiable OAuth scopes; environment tokens must already have the required
  scope. Then runs `gh config set git_protocol ssh --host github.com` so GitHub
  Git operations use SSH.
- When more than one account is authenticated, prints the active login and asks
  for confirmation before adding the key.
- Generates an ed25519 key at `~/.ssh/id_github-personal` with no passphrase,
  commented with `git config user.email` (falling back to `user@host`). An
  existing key is reused rather than overwritten.
- Writes a delimited block to `~/.ssh/config` so `git@github.com` uses the key:

  ~~~text
  Host github.com
    IdentityFile "~/.ssh/id_github-personal"
    IdentitiesOnly yes
  ~~~

  Re-runs replace the block. Unmatched or nested block markers cause the script
  to refuse the rewrite, preserving the existing file. If an unmanaged
  `Host github.com` entry already exists, the script refuses to edit the file
  and asks you to merge by hand. It
  validates the proposed configuration with `ssh -G` before replacing the file,
  including settings from `Match` blocks, `Include` files, and system config.
  Invalid configuration or effective settings that add another identity or
  disable `IdentitiesOnly` are rejected. OpenSSH keeps the first
  `IdentitiesOnly` value and accumulates `IdentityFile` entries. Restrict
  conflicting settings so they no longer match `github.com`, then rerun.
  The generated identity path is quoted to support home directories containing
  spaces. Because `~/.ssh/config` is written by the script (not stowed),
  `doctor.sh` does not track it.
- Registers the public key with `gh ssh-key add --title`, prompting for the
  title when `--title` is omitted, and skips the upload when the key's
  fingerprint is already on the account.
- Verifies the result with `ssh -T git@github.com` (treating GitHub's exit code
  1 as success) and confirms the greeting names the selected account, so a
  different registered key authenticating as another account fails the run. It
  then prints the account, fingerprint, and public key.
- `--dry-run` performs no network calls, prompts, or writes; it reports whether
  `gh` is authenticated and what the key, config, and upload steps would do.
  It checks block markers but defers OpenSSH validation until a real run because
  `Match exec` predicates can execute commands while evaluating configuration.

### `macos-defaults.sh`

```sh
bash macos-defaults.sh            # preview planned commands (default)
bash macos-defaults.sh --apply    # back up, then write preferences
bash macos-defaults.sh --check    # compare stored values with the profile
```

Applies a curated set of macOS preference tweaks to the current machine.
macOS only; run as your regular user, **never** with `sudo` (it exits when run
as root or on a non-Darwin system). It is a snapshot captured on macOS 27 on
Apple Silicon, not an exhaustive factory-default diff, and it warns when the
running major version differs from the one it was captured on.

- `--dry-run` (the default) prints the `defaults write` commands it would run
  and changes nothing.
- `--apply` backs up every affected preference domain before the first write,
  then applies the settings. It refuses to run while System Settings is open;
  close it first.
- Backups are written under
  `~/Library/Application Support/macos-defaults/backups/<timestamp>/` with
  restrictive permissions, one plist export per domain (or an `.absent` marker
  when a domain does not exist yet). These backups can include private app
  state.
- Affected domains: `NSGlobalDomain` (plus its `-currentHost` scope),
  `com.apple.dock`, `com.apple.AppleMultitouchTrackpad`, and
  `com.apple.driver.AppleBluetoothMultitouch.trackpad`.
- `--check` reads the stored values and lists any that differ from the profile,
  exiting non-zero when there is at least one difference. It changes nothing.
- Covers appearance (automatic Light/Dark switching), keyboard repeat delay and
  rate, trackpad gestures (tap-to-click, three-finger drag), and Dock settings
  (autohide, magnification, icon sizes, recent applications). Display and other
  hardware-dependent settings are intentionally out of scope.
- Does not restart apps or log you out. Log out and back in afterwards, then
  verify the UI and run `--check`.

## Per-host values

Values that differ by operating system -- the Homebrew environment and
`PNPM_HOME` -- live in `stow/zsh/.config/zsh/.zprofile`, branched on
`uname -s`. Keeping them in tracked config means no per-host file has to be
seeded or edited by hand.

## Packages

`brew/Brewfile.base` is **formulae only** and holds every shared package.
Linux-specific formulae live in `Brewfile.headless-linux`.
`install.sh` installs `Brewfile.base` first and then the host's Brewfile,
keeping shared packages defined once without relying on a Brewfile include
directive.
Casks are macOS GUI apps and live only in the per-host Brewfiles
(`Brewfile.mac` carries workstation apps; `Brewfile.headless-mac` carries only
`betterdisplay`, which provides the virtual display, and `rustdesk`, plus
fonts).

Tailscale is distributed per host. It is deliberately absent from
`Brewfile.base`, because macOS cannot run the open-source CLI daemon and the
GUI app at the same time. The macbook installs the GUI cask (`tailscale-app`)
through the manual steps (it needs an administrator password); the headless Mac
mini and the Linux mini PC install the CLI formula (`tailscale`).

RustDesk is installed on every host. On macOS it is the `rustdesk` cask. Linux
has no Homebrew formula, and the cask only ships an AppImage, which cannot
provide the boot-time service unattended access needs; so `install.sh` resolves
the current `rustdesk-unattended-wayland` preview from the GitHub **nightly**
release (highest version, since nightly keeps older builds), downloads the
`.deb` into `~/Downloads`, and prints a `sudo apt install` manual step. The
build adds pre-login access on Wayland and is a drop-in replacement for the
standard package (`Conflicts`/`Replaces`/`Provides: rustdesk`); fall back to
`rustdesk-<version>-x86_64.deb` if the preview misbehaves.

Unattended access needs a permanent password plus the running service, so only
the headless Mac mini and the Linux mini PC carry RustDesk manual steps; the
macbook gets the client for connecting out. macOS also requires Screen
Recording, Accessibility, and Input Monitoring permissions, which must be
granted by hand.

Tuxera NTFS, Zoom, Microsoft Teams, and the Tailscale GUI require an
administrator password, so they are installed separately. On both Macs, the
printed manual steps and `manual-steps.md` include
`brew install --cask tuxera-ntfs`. For `HOST=macbook`, they also include
`brew install --cask zoom microsoft-teams` and
`brew install --cask tailscale-app`. Run these commands interactively after
provisioning.

### Language runtimes

Node, Bun and Python are deliberately absent. `install.sh` automates Node,
pnpm, and Bun installation:

- **Node** -- via `fnm`. Reuses the existing fnm default, otherwise selects
  the newest installed stable version and makes it the default. If none is
  installed, runs `fnm install latest` and sets that version as the default.
  A system Node installation alone does not satisfy this requirement.
- **pnpm** -- via the [official install script](https://pnpm.io/installation)
  at `https://get.pnpm.io/install.sh`. Installs the latest stable release into
  `~/Library/pnpm` on macOS or `~/.local/share/pnpm` on Linux (`PNPM_HOME`).
- **Bun** -- via the [official install script](https://bun.com/docs/installation)
  at `https://bun.com/install`. Installs the latest stable release into
  `~/.bun`; macOS provides `unzip`, and Linux installs it through
  `brew/Brewfile.headless-linux`.
- **Python** -- the system interpreter.

pnpm and Bun are installed only when missing from the configured runtime
paths and `PATH`. Neither uses npm or Corepack. Install scripts are downloaded
to temporary files, executed only after a successful download, and cleaned up
afterwards. Shell configuration remains managed by Stow: pnpm receives
`PNPM_NO_MODIFY_PATH=1`, and Bun runs with `SHELL=/bin/sh` and its bin directory
already on `PATH`.

The coding agent scripts are downloaded to temporary files before execution.
Their executable directories (`~/.local/bin` and `~/.opencode/bin`) are added
to the stowed shell configuration. OpenCode's installer does not edit shell
configuration. Agent credentials and configuration are not migrated.

zsh is also not in the Brewfiles. macOS ships zsh as the default login shell,
and on Linux `bootstrap.sh` installs zsh with `apt-get` so it is registered in
`/etc/shells` and can be selected with `chsh`.

## Adopting existing files

On a machine that already has real config files at the target paths, `stow`
refuses to overwrite them. The safe fix is to move the real file aside (or
back it up) and re-run `install.sh`, or to let Stow take ownership of the
existing file:

```sh
# Review first: this replaces the repo copy with the file already on disk.
stow --adopt --target="$HOME" --dir="$PWD/stow" <package>
```

`install.sh` never runs `--adopt` for you.

## Caveats

- `btop` sets `save_config_on_exit = true`, so on exit it rewrites its
  symlinked `~/.config/btop/btop.conf` (a file symlink into the repo); expect
  that file to appear in `git status` after you change btop settings.
  `--no-folding` keeps other runtime state (for example `micro`'s
  `buffers/history`) outside the repo.
- `ghostty/theme` is a duplicate of `ghostty/config` and is kept as-is.
- On Linux, Ubuntu's default sudo `secure_path` does not include the Homebrew
  prefix (`/home/linuxbrew/.linuxbrew/bin`), so `sudo brew` / `sudo tailscale`
  fail with "command not found". The Tailscale steps `install.sh` prints for
  Linux therefore use resolved absolute executable paths.
- Agent tooling (opencode, codex, claude, herdr, supacode) is intentionally
  **not** migrated: those configs contain secrets, absolute paths, and runtime
  state. Keep them out of the repo.
- RustDesk's own configuration is deliberately **not** stowed for the same
  reason: it holds the permanent password hash and private key.
- `migrate-storage.zsh` was a one-off migration and is not stowed.
