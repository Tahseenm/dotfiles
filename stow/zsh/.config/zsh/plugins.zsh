# =========================================================
# Plugins
# =========================================================

ZPLUGINDIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"

_zplugin_load() {
  local plugin_path="${ZPLUGINDIR}/${2}"
  if [[ ! -d "$plugin_path" ]]; then
    mkdir -p "$ZPLUGINDIR"
    echo "Installing ${2}..."
    git clone --depth=1 "https://github.com/${1}/${2}" "$plugin_path" \
      || { echo "ERROR: failed to install ${2}" >&2; return 1; }
  fi
  source "${plugin_path}/${2}.plugin.zsh"
}

zplugin-update() {
  local dir
  for dir in "${ZPLUGINDIR}"/*/; do
    echo "Updating ${dir:t}..."
    git -C "$dir" pull --ff-only
  done
}

# Replace Zsh completion menu with fzf-powered completion.
_zplugin_load aloxaf fzf-tab

# Suggests commands as you type, based on your shell history.
_zplugin_load zsh-users zsh-autosuggestions

# Search for history entries using UP and DOWN arrows, based on the current command line.
_zplugin_load zsh-users zsh-history-substring-search

# Highlights shell syntax while you edit commands, including invalid syntax.
_zplugin_load zdharma-continuum fast-syntax-highlighting
