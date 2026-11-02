# =========================================================
# Keybindings
# =========================================================

# Up/Down -> history search by substring (^[[A/^[[B are up/down arrow escape codes)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Enable history substring search for arrow keys in application mode
bindkey '^[OA' history-substring-search-up
bindkey '^[OB' history-substring-search-down
