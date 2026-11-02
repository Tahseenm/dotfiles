#!/usr/bin/env bash
#
# bootstrap.sh -- take a bare machine to the point where install.sh can run.
#
# Installs only what install.sh and the shell config need: Homebrew, git,
# stow, dasel, (on macOS) mas, and (on Linux) zsh. Safe to re-run.

set -euo pipefail

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Homebrew's installer uses `sudo -n` when NONINTERACTIVE is set, so it cannot
# prompt for a password. Acquire (and cache) admin rights first; otherwise a
# fresh machine aborts with "Insufficient permissions" before installing.
ensure_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  local sudo_bin
  sudo_bin="$(command -v sudo || true)"
  if [[ -z "$sudo_bin" ]]; then
    log "sudo not found; continuing (Homebrew will run without it)."
    return 0
  fi
  if "$sudo_bin" -n true 2>/dev/null; then
    return 0
  fi
  log "Homebrew needs administrator access; you may be prompted for your password."
  "$sudo_bin" -v || die "Could not obtain administrator access (sudo)."
}

install_homebrew_mac() {
  if have brew; then
    log "Homebrew already installed."
  else
    log "Installing Homebrew (macOS)..."
    ensure_sudo
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # Make brew available in this process (Apple Silicon prefix).
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

install_zsh_linux() {
  if have zsh; then
    log "zsh already installed."
    return
  fi
  if have apt-get; then
    log "Installing zsh (apt-get)..."
    sudo apt-get update
    sudo apt-get install -y zsh
  else
    die "zsh is not installed and apt-get was not found. Install zsh, then re-run bootstrap.sh."
  fi
}

install_homebrew_linux() {
  if have brew; then
    log "Homebrew already installed."
  else
    log "Installing Homebrew (Linux)..."
    ensure_sudo
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

main() {
  local os
  os="$(uname -s)"

  case "$os" in
    Darwin)
      if ! xcode-select -p >/dev/null 2>&1; then
        log "Requesting Xcode Command Line Tools install..."
        xcode-select --install >/dev/null 2>&1 || true
        die "Xcode Command Line Tools are required. Finish the install, then re-run bootstrap.sh."
      fi
      install_homebrew_mac
      log "Installing bootstrap packages..."
      brew install git stow dasel mas
      ;;
    Linux)
      install_zsh_linux
      install_homebrew_linux
      log "Installing bootstrap packages..."
      brew install git stow dasel
      ;;
    *)
      die "Unsupported operating system: $os"
      ;;
  esac

  log "bootstrap complete. Next: HOST=<host> ./install.sh"
}

main "$@"
