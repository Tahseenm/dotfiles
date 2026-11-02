#!/usr/bin/env bash
#
# install.sh -- idempotent provisioning: Homebrew Bundle + GNU Stow + runtimes.
#
# Usage: HOST=<host> ./install.sh [--dry-run]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_DIR="$REPO_DIR/hosts"
STOW_DIR="$REPO_DIR/stow"

DRY_RUN=0

# Path to the RustDesk .deb downloaded for Linux, or empty when not applicable.
RUSTDESK_DEB=""

list_hosts() {
  local f
  for f in "$HOSTS_DIR"/*.toml; do
    [[ -e "$f" ]] || continue
    basename "$f" .toml
  done
}

usage() {
  cat <<EOF
Usage: HOST=<host> $(basename "$0") [--dry-run]

Resolves the host manifest at hosts/<host>.toml, installs its Brewfile,
stows its packages, and installs missing runtimes and coding agents. With --dry-run nothing
is changed.

Available hosts:
$(list_hosts | sed 's/^/  /')
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf "error: '%s' not found. Run ./bootstrap.sh first.\n" "$1" >&2
    exit 1
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Download completely before executing, and clean up on success or failure.
# Remaining arguments are environment variables for the upstream installer.
install_from_url() (
  local label="$1" url="$2" interpreter="$3" installer
  shift 3
  command -v curl >/dev/null 2>&1 || die 'curl is required to download installers.'
  installer="$(mktemp "${TMPDIR:-/tmp}/dotfiles-runtime.XXXXXX")" || die 'Could not create a temporary installer.'
  trap 'rm -f "$installer"' EXIT
  printf 'Installing %s...\n' "$label"
  curl -fsSL "$url" -o "$installer" || die "Could not download the $label installer."
  if [[ "$label" == OpenCode ]]; then
    env "$@" "$interpreter" "$installer" --no-modify-path || die "$label installation failed."
  else
    env "$@" "$interpreter" "$installer" || die "$label installation failed."
  fi
)

install_agents() {
  local tool
  export PATH="$PATH:$HOME/.local/bin:$HOME/.opencode/bin"
  for tool in codex claude opencode; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf 'already installed: %s (%s)\n' "$tool" "$(command -v "$tool")"
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'would install: %s using its official install script\n' "$tool"
      continue
    else
      case "$tool" in
        codex) install_from_url Codex https://chatgpt.com/codex/install.sh sh CODEX_NON_INTERACTIVE=1 ;;
        claude) install_from_url 'Claude Code' https://claude.ai/install.sh bash ;;
        opencode) install_from_url OpenCode https://opencode.ai/v2/install bash ;;
      esac
    fi
    if [[ "$DRY_RUN" -eq 0 ]]; then
      "$tool" --version || die "$tool version verification failed."
    fi
  done
}

# The Wayland unattended preview is published under the `nightly` release, not
# the stable one, and nightly keeps older preview builds side by side, so select
# the highest version rather than the first match.
rustdesk_wayland_deb_url() {
  local api="$1"
  curl -fsSL "$api" 2>/dev/null \
    | grep -oE 'https://[^"]*rustdesk-unattended-wayland-[0-9][^"]*-x86_64\.deb' \
    | sort -V | tail -n 1 || true
}

# Download to a temporary file in the destination directory and rename it into
# place only once the transfer succeeds, so an interrupted run can never leave a
# partial package behind that a later run mistakes for a complete download.
download_rustdesk_deb() (
  local url="$1" file="$2" tmp
  tmp="$(mktemp "$(dirname "$file")/.rustdesk-XXXXXX")" || return 1
  trap 'rm -f "$tmp"' EXIT INT TERM
  curl -fsSL "$url" -o "$tmp" || return 1
  mv -f "$tmp" "$file"
)

# RustDesk has no Homebrew formula. On Linux the .deb is required for the
# boot-time service that unattended access depends on, and installing it needs
# sudo, so install.sh only downloads the package and the manual step installs
# it. The Wayland unattended build adds pre-login access and is a drop-in
# replacement for the standard package (Conflicts/Replaces/Provides: rustdesk).
install_rustdesk_linux() {
  local url dest file
  if ! command -v curl >/dev/null 2>&1; then
    printf 'skipping RustDesk: curl is required to resolve the download URL.\n'
    return 0
  fi
  # The preview lives in the nightly release; fall back to the latest stable
  # release in case the preview has graduated into it.
  url="$(rustdesk_wayland_deb_url 'https://api.github.com/repos/rustdesk/rustdesk/releases/tags/nightly')"
  if [[ -z "$url" ]]; then
    url="$(rustdesk_wayland_deb_url 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest')"
  fi
  if [[ -z "$url" ]]; then
    printf 'warning: could not resolve the RustDesk Wayland .deb (network or GitHub API rate limit).\n' >&2
    return 0
  fi
  dest="$HOME/Downloads"
  file="$dest/$(basename "$url")"
  RUSTDESK_DEB="$file"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would download: %s\n  to: %s\n' "$url" "$file"
    return 0
  fi
  if [[ -f "$file" ]]; then
    printf 'already downloaded: %s\n' "$file"
    return 0
  fi
  if ! mkdir -p "$dest"; then
    printf 'warning: could not create %s\n' "$dest" >&2
    RUSTDESK_DEB=""
    return 0
  fi
  printf 'Downloading RustDesk (.deb) to %s\n' "$file"
  if download_rustdesk_deb "$url" "$file"; then
    return 0
  fi
  printf 'warning: could not download %s\n' "$url" >&2
  RUSTDESK_DEB=""
}

install_node() {
  local fnm_env node_version installed_versions
  command -v fnm >/dev/null 2>&1 || die 'fnm is missing after Homebrew Bundle; check the shared Brewfile installation.'
  fnm_env="$(fnm env --shell bash)" || die 'Could not initialize fnm.'
  eval "$fnm_env"

  node_version="$(fnm default 2>/dev/null || true)"
  if [[ "$node_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] && fnm use "$node_version"; then
    printf 'Using existing Node default: %s\n' "$node_version"
    return
  fi

  installed_versions="$(NO_COLOR=1 fnm list)" || die 'Could not list installed Node versions.'
  node_version="$(printf '%s\n' "$installed_versions" \
    | sed -nE 's/^[*[:space:]]*v([0-9]+\.[0-9]+\.[0-9]+)([[:space:]].*)?$/\1/p' \
    | sort -t . -k1,1n -k2,2n -k3,3n | tail -n 1)"
  if [[ -n "$node_version" ]]; then
    fnm use "$node_version" || die "Could not activate Node $node_version."
  else
    fnm install latest || die 'Could not install the latest Node release.'
    fnm use latest || die 'Could not activate the latest Node release.'
  fi
  node_version="$(fnm current)" || die 'Could not determine the active Node version.'
  fnm default "$node_version" || die 'Could not set the default Node version.'
}

install_runtimes() {
  local tool
  # Match the paths managed by the stowed zsh configuration without sourcing it.
  case "$(uname -s)" in
    Darwin) export PNPM_HOME="$HOME/Library/pnpm" ;;
    Linux) export PNPM_HOME="$HOME/.local/share/pnpm" ;;
    *) die 'Runtime installation supports macOS and Linux only.' ;;
  esac
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$PNPM_HOME/bin:$BUN_INSTALL/bin:$PATH"

  # fnm env creates runtime state, so even initialization must wait for apply.
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would ensure: fnm-managed Node (reuse default/newest installed; otherwise install latest and set default)\n'
    for tool in pnpm bun; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '  already installed: %s (%s)\n' "$tool" "$(command -v "$tool")"
      else
        case "$tool" in
          pnpm) printf 'would install: pnpm from https://get.pnpm.io/install.sh into %s (without modifying shell config)\n' "$PNPM_HOME" ;;
          bun) printf 'would install: Bun from https://bun.com/install into %s (without modifying shell config)\n' "$BUN_INSTALL" ;;
        esac
      fi
    done
    return
  fi

  install_node
  if ! command -v pnpm >/dev/null 2>&1; then
    install_from_url pnpm https://get.pnpm.io/install.sh sh PNPM_NO_MODIFY_PATH=1 SHELL=/bin/sh
  fi
  if ! command -v bun >/dev/null 2>&1; then
    command -v unzip >/dev/null 2>&1 || die 'unzip is required by the Bun installer; on Linux, check the host Brewfile installation.'
    # /bin/sh avoids upstream shell config edits; Stow already manages PATH.
    install_from_url Bun https://bun.com/install bash SHELL=/bin/sh
  fi
  for tool in node pnpm bun; do
    printf '%s version: ' "$tool"
    "$tool" --version || die "$tool version verification failed."
  done
}

# Read a single value from a TOML manifest (dasel v3 reads from stdin).
toml_scalar() {
  dasel -i toml -o json "$2" < "$1" | tr -d '"'
}

# Read a TOML string array, one element per line.
toml_array() {
  dasel -i toml -o json "$2" < "$1" \
    | tr -d '[]"' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' || true
}

# Manual steps are defined once and rendered twice: as plain text for the
# terminal and as a Markdown checklist in the gitignored manual-steps.md.
# Each entry is "<label><TAB><command>"; an empty command marks a note.
manual_steps() {
  printf '%s\t%s\n' 'Sign in to GitHub' 'gh auth login'
  printf '%s\t%s\n' 'Sign in to Codex' 'codex login'
  printf '%s\t%s\n' 'Sign in to Claude Code' 'claude auth login'
  printf '%s\t%s\n' 'Connect integration in OpenCode TUI' '/connect'

  # Tailscale differs by host: the workstation Mac runs the GUI app, while the
  # headless hosts run the CLI daemon.
  case "$HOST" in
    macbook)
      printf '%s\t%s\n' 'Install Tailscale (requires administrator password)' 'brew install --cask tailscale-app'
      printf '%s\t%s\n' 'Tailscale' 'open -a Tailscale   (then sign in to your tailnet)'
      ;;
    linux-pc)
      # Ubuntu's sudo secure_path excludes the Homebrew prefix, so `sudo brew`
      # and `sudo tailscale` fail with "command not found" even when the user's
      # own PATH includes them. Print resolved absolute paths instead.
      local brew_bin ts_bin
      brew_bin="$(command -v brew 2>/dev/null || printf '%s/bin/brew' "${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}")"
      ts_bin="$(command -v tailscale 2>/dev/null || printf '%s/bin/tailscale' "${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}")"
      printf '%s\t%s\n' 'Tailscale daemon' "sudo $brew_bin services start tailscale"
      printf '%s\t%s\n' 'Tailscale' "sudo $ts_bin up"
      ;;
    *)
      printf '%s\t%s\n' 'Tailscale daemon' 'sudo brew services start tailscale'
      printf '%s\t%s\n' 'Tailscale' 'sudo tailscale up'
      ;;
  esac

  # RustDesk is installed on every host; unattended access is configured only on
  # the headless hosts. The permanent password is never stored in the repo.
  case "$HOST" in
    linux-pc)
      if [[ -n "$RUSTDESK_DEB" ]]; then
        printf '%s\t%s\n' 'Install RustDesk (requires administrator password)' "sudo apt install -y $RUSTDESK_DEB"
      else
        printf '%s\t%s\n' 'Install RustDesk (requires administrator password)' 'download the rustdesk-unattended-wayland .deb from GitHub, then: sudo apt install -y <file>.deb'
      fi
      printf '%s\t%s\n' 'RustDesk unattended password' "sudo rustdesk --password '<strong-password>'   (needs root; do not reuse the OS password)"
      ;;
    mac-mini)
      printf '%s\t%s\n' 'RustDesk permissions (required for unattended)' 'launch RustDesk, then grant Screen Recording, Accessibility, and Input Monitoring in System Settings > Privacy & Security'
      printf '%s\t%s\n' 'RustDesk unattended access' 'set a permanent password in Settings > Security, and confirm the Service is running under Settings > General'
      ;;
  esac
  case "$(uname -s)" in
    Linux)
      printf '%s\t%s\n' 'Login shell' "chsh -s $(command -v zsh || printf '/usr/bin/zsh')   (then log out and back in)"
      ;;
    Darwin)
      printf '%s\t%s\n' 'Install Tuxera NTFS (requires administrator password)' 'brew install --cask tuxera-ntfs'
      if [[ "$HOST" == macbook ]]; then
        printf '%s\t%s\n' 'Install Zoom and Microsoft Teams (requires administrator password)' 'brew install --cask zoom microsoft-teams'
      fi
      printf '%s\t%s\n' 'macOS: sign in / grant permissions to any GUI apps you use.' ''
      ;;
  esac
}

print_manual_steps() {
  printf '\nManual steps (cannot be automated):\n'
  local label cmd
  while IFS=$'\t' read -r label cmd; do
    if [[ -n "$cmd" ]]; then
      printf '  - %s: %s\n' "$label" "$cmd"
    else
      printf '  - %s\n' "$label"
    fi
  done < <(manual_steps)
}

write_manual_steps() {
  local out="$REPO_DIR/manual-steps.md"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would write: %s\n' "$out"
    return
  fi
  local label cmd
  {
    printf '# Manual steps -- %s (%s)\n\n' "$HOST" "$(date +%Y-%m-%d)"
    printf "Generated by \`HOST=%s ./install.sh\`. Safe to edit or delete; this file is git-ignored.\n\n" "$HOST"
    while IFS=$'\t' read -r label cmd; do
      if [[ -n "$cmd" ]]; then
        printf -- '- [ ] %s: %s\n' "$label" "\`$cmd\`"
      else
        printf -- '- [ ] %s\n' "$label"
      fi
    done < <(manual_steps)
  } > "$out"
  printf 'Wrote %s\n' "$out"
}

if [[ -z "${HOST:-}" ]]; then
  printf 'error: HOST is not set.\n' >&2
  printf 'Set it to one of:\n' >&2
  list_hosts | sed 's/^/  /' >&2
  printf 'Example: HOST=macbook ./install.sh\n' >&2
  exit 1
fi

MANIFEST="$HOSTS_DIR/$HOST.toml"
if [[ ! -f "$MANIFEST" ]]; then
  printf "error: unknown HOST '%s' (no %s).\n" "$HOST" "$MANIFEST" >&2
  printf 'Valid hosts:\n' >&2
  list_hosts | sed 's/^/  /' >&2
  exit 1
fi

if [[ "$HOST" == macbook ]]; then
  printf 'Have you signed into the App Store? [y/N] ' >&2
  if ! IFS= read -r app_store_signed_in; then
    die 'App Store sign-in confirmation is required. Sign in, then rerun install.sh.'
  fi
  case "$app_store_signed_in" in
    [yY]|[yY][eE][sS]) ;;
    *) die 'Sign in to the App Store, then rerun install.sh.' ;;
  esac
fi

# Homebrew's prefix is not on PATH on a fresh machine: bootstrap.sh evaluates
# `brew shellenv` only inside its own subprocess. Initialize the detected
# environment here before requiring its commands.
if ! command -v brew >/dev/null 2>&1; then
  for brew_prefix in "${HOMEBREW_PREFIX:-}" /opt/homebrew /home/linuxbrew/.linuxbrew; do
    [[ -n "$brew_prefix" && -x "$brew_prefix/bin/brew" ]] || continue
    eval "$("$brew_prefix/bin/brew" shellenv)"
    break
  done
fi

require brew
require stow
require dasel

# --- manifest --------------------------------------------------------------

brew_file_rel="$(toml_scalar "$MANIFEST" 'brew.file')"
BREWFILE="$REPO_DIR/$brew_file_rel"
if [[ ! -f "$BREWFILE" ]]; then
  printf 'error: Brewfile not found: %s\n' "$BREWFILE" >&2
  exit 1
fi

packages=()
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] && packages+=("$pkg")
done < <(toml_array "$MANIFEST" 'stow.packages')

if [[ "${#packages[@]}" -eq 0 ]]; then
  printf 'error: no stow packages listed in %s\n' "$MANIFEST" >&2
  exit 1
fi

# --- Homebrew Bundle -------------------------------------------------------
#
# Homebrew Bundle has no include directive, so the shared base is installed
# first, then the host-specific Brewfile.

BASE_BREWFILE="$REPO_DIR/brew/Brewfile.base"
if [[ ! -f "$BASE_BREWFILE" ]]; then
  printf 'error: base Brewfile not found: %s\n' "$BASE_BREWFILE" >&2
  exit 1
fi

for bf in "$BASE_BREWFILE" "$BREWFILE"; do
  brew_args=(bundle install --file="$bf" --no-upgrade)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would run: brew %s\n' "${brew_args[*]}"
    if brew bundle check --no-upgrade --file="$bf" >/dev/null 2>&1; then
      printf '  up to date: %s\n' "$bf"
    else
      printf '  would install/change: %s\n' "$bf"
    fi
  else
    printf 'brew %s\n' "${brew_args[*]}"
    brew "${brew_args[@]}"
  fi
done

# --- GNU Stow --------------------------------------------------------------

stow_args=(--restow --no-folding --target="$HOME" --dir="$STOW_DIR")
[[ "$DRY_RUN" -eq 1 ]] && stow_args+=(-n -v)

for pkg in "${packages[@]}"; do
  if [[ ! -d "$STOW_DIR/$pkg" ]]; then
    printf 'error: stow package not found: %s\n' "$STOW_DIR/$pkg" >&2
    exit 1
  fi
  printf 'stow %s %s\n' "${stow_args[*]}" "$pkg"
  stow "${stow_args[@]}" "$pkg"
done

# --- Language runtimes -----------------------------------------------------

install_runtimes

# --- Global pnpm packages --------------------------------------------------

if command -v node >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    node "$REPO_DIR/pnpm-global/install.cjs" --dry-run
  else
    node "$REPO_DIR/pnpm-global/install.cjs"
  fi
elif [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'would ensure global pnpm packages from %s:\n' "$REPO_DIR/pnpm-global/package.json"
  cat "$REPO_DIR/pnpm-global/package.json"
else
  die 'Node is required to install global pnpm packages.'
fi

# --- Coding agents ---------------------------------------------------------

install_agents

# --- RustDesk (headless Linux) ---------------------------------------------

if [[ "$(uname -s)" == Linux ]]; then
  install_rustdesk_linux
fi

print_manual_steps
write_manual_steps
