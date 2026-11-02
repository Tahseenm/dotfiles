# =========================================================
# FZF
# =========================================================

# Show files, include hidden and skip heavy directories that can slow results. Remove the ./ prefix. 
export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git --exclude node_modules --exclude dist'

# Ctrl-T uses fd
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# UI
export FZF_DEFAULT_OPTS="
  --height=60%
  --layout=reverse
  --border=rounded
  --prompt='  '
  --pointer='  '
  --preview-window=right:65%:wrap:border-left
  ${FZF_CATPPUCCIN_MOCHA[*]}
"

export _FZF_PREVIEW_CMD='bat --color=always --style=plain,numbers --line-range=:500 -- {}'
export FZF_CTRL_T_OPTS="--preview '$_FZF_PREVIEW_CMD'"

# Initialize shell integration only in an interactive terminal.
if [[ -o interactive && -t 0 && -t 1 ]] && (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi
