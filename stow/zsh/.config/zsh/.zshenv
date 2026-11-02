# Disable macOS Terminal shell-session restoration
export SHELL_SESSIONS_DISABLE=1

# Set up relevant XDG base directories.
# Spec: https://specifications.freedesktop.org/basedir-spec/latest/index.html
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}

# Make sure directories actually exist
xdg_base_dirs=("$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME")
for dir in "${xdg_base_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
done

# =========================================================
# Editor
# =========================================================

# Default editor used by git, crontab, etc.
export EDITOR="micro"
export VISUAL="micro"


# =========================================================
# PATH
# =========================================================

# Keep the first occurrence of each directory in PATH.
typeset -U path PATH

# Personal binaries/scripts
path=("$HOME/.local/bin" $path)
export PATH
