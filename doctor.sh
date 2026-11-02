#!/usr/bin/env bash
#
# doctor.sh -- read-only drift report. Changes nothing.
#
# Reports:
#   - brew bundle check result for every Brewfile
#   - every expected stow symlink (and its target) for every host manifest
#   - git status of this repository

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_DIR="$REPO_DIR/hosts"
STOW_DIR="$REPO_DIR/stow"

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$*"; }

list_hosts() {
  local f
  for f in "$HOSTS_DIR"/*.toml; do
    [[ -e "$f" ]] || continue
    basename "$f" .toml
  done
}

toml_array() {
  dasel -i toml -o json "$2" < "$1" \
    | tr -d '[]"' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' || true
}

# --- Homebrew Bundle -------------------------------------------------------

# Homebrew's prefix is not on PATH on a fresh machine (bootstrap.sh only
# evaluates `brew shellenv` inside its own subprocess). Initialize the detected
# environment so the checks below do not falsely report "brew not found".
if ! have brew; then
  for brew_prefix in "${HOMEBREW_PREFIX:-}" /opt/homebrew /home/linuxbrew/.linuxbrew; do
    [[ -n "$brew_prefix" && -x "$brew_prefix/bin/brew" ]] || continue
    eval "$("$brew_prefix/bin/brew" shellenv)"
    break
  done
fi

section "Homebrew Bundle"
if have brew; then
  for f in "$REPO_DIR"/brew/Brewfile.*; do
    [[ -e "$f" ]] || continue
    if brew bundle check --no-upgrade --file="$f" >/dev/null 2>&1; then
      printf 'ok:    %s\n' "$(basename "$f")"
    else
      printf 'drift: %s -- run: brew bundle install --file=%s\n' "$(basename "$f")" "$f"
    fi
  done
else
  printf 'skipped: brew not found\n'
fi

# --- Stow ------------------------------------------------------------------

# Stow's `--simulate` only reports whether links *could* be created without
# conflicts, so it stays silent when links are missing entirely. Verify the
# expected symlinks and their targets instead.
section "Stow (installed symlinks)"
if have dasel; then
  for host in $(list_hosts); do
    manifest="$HOSTS_DIR/$host.toml"
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] || continue
      if [[ ! -d "$STOW_DIR/$pkg" ]]; then
        printf 'drift: [%s] %s -- package missing: %s\n' "$host" "$pkg" "$STOW_DIR/$pkg"
        continue
      fi
      bad=0
      bad_rels=()
      while IFS= read -r file; do
        rel="${file#"$STOW_DIR/$pkg/"}"
        link="$HOME/$rel"
        if [[ ! -L "$link" || ! "$link" -ef "$file" ]]; then
          bad=$((bad + 1))
          bad_rels+=("$rel")
        fi
      done < <(find "$STOW_DIR/$pkg" -type f)
      if [[ "$bad" -eq 0 ]]; then
        printf 'ok:    [%s] %s\n' "$host" "$pkg"
      else
        printf 'drift: [%s] %s -- %s link(s) missing or incorrect\n' "$host" "$pkg" "$bad"
        printf '    %s\n' "${bad_rels[@]}"
      fi
    done < <(toml_array "$manifest" 'stow.packages')
  done
else
  printf 'skipped: dasel not found\n'
fi

# --- Repository ------------------------------------------------------------

section "Repository"
git -C "$REPO_DIR" status --short --branch
