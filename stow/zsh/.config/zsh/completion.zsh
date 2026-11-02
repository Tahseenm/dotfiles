# =========================================================
# Completion
# =========================================================

cache_directory="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$cache_directory" ]] || mkdir -p "$cache_directory"

## Use cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$cache_directory/completion-cache"

# Load the completion system and enable it
autoload -Uz compinit && compinit -d "$cache_directory/compinit-dumpfile"

# Native pnpm completion
source "$ZDOTDIR/completions/pnpm.zsh"

zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'

# Disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false

# Preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons --group-directories-first $realpath'

# NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
zstyle ':fzf-tab:*' fzf-flags \
  --bind=tab:accept \
  --border=rounded \
  --layout=reverse \
  --prompt="  " \
  --highlight-line \
  "${FZF_CATPPUCCIN_MOCHA[@]}"

# Completion pipeline: exact -> ignored -> approximate (max 2 errors)
zstyle ':completion:*' completer _complete _ignored _approximate
zstyle ':completion:*' max-errors 2
