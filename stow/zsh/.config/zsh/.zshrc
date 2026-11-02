export MICRO_TRUECOLOR=1
source "$ZDOTDIR/theme.zsh"


# =========================================================
# History
# =========================================================

# Set up history file in XDG_STATE_HOME
if [[ ! -d "$XDG_STATE_HOME/zsh" ]]; then
  (umask 077; command mkdir -p -- "$XDG_STATE_HOME/zsh")
fi
HISTFILE="$XDG_STATE_HOME/zsh/history"

HISTSIZE=100000 # Total kept in session
SAVEHIST=50000  # Total saved to history file

setopt EXTENDED_HISTORY       # Record timestamp of command in HISTFILE
setopt APPEND_HISTORY         # Append commands to history file instead of overwrite
setopt SHARE_HISTORY          # Share history across all open ZSH sessions
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicates, not just consecutive ones
setopt HIST_IGNORE_SPACE      # Ignore commands that start with space
setopt HIST_EXPIRE_DUPS_FIRST # Delete duplicates first when HISTFILE exceeds HISTSIZE
setopt HIST_FIND_NO_DUPS      # Skip duplicates when searching history
setopt HIST_VERIFY            # Show command with history expansion before running it
setopt HIST_REDUCE_BLANKS     # Trim extra spaces in commands before saving


# =========================================================
# Shell behaviour
# =========================================================

setopt AUTOCD             # Changes directories by typing folder name
setopt NOBEEP             # Disable terminal bell
setopt NUMERIC_GLOB_SORT  # Sort file10 after file9, not after file1


# =========================================================
# Smart directory navigation
# =========================================================

# Initialize zoxide and hook into `cd`
eval "$(zoxide init zsh --cmd cd)"


# =========================================================
# Completion
# =========================================================

source "$ZDOTDIR/completion.zsh"


# =========================================================
# Fuzzy finder
# =========================================================

source "$ZDOTDIR/fzf.zsh"


# =========================================================
# Modular Config Files
# =========================================================

# Aliases
source "$ZDOTDIR/aliases.zsh"

# Custom keybindings
source "$ZDOTDIR/bindings.zsh"

# Plugins and plugin manager
source "$ZDOTDIR/plugins.zsh"

# Prompt/theme
source "$ZDOTDIR/prompt.zsh"


# =========================================================
# Node
# =========================================================

# Fast Node Manager (fnm)
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# PNPM_HOME is set in .zprofile (its path differs by OS).

# Bun
export BUN_INSTALL="$HOME/.bun"
path=("$BUN_INSTALL/bin" $path)
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"


# =========================================================
# Coding Agents
# =========================================================

# OpenCode
path=("$HOME/.opencode/bin" $path)
