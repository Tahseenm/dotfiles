alias l='eza -lAh -F auto --group-directories-first --git --icons --no-user'
alias tree='eza --icons --tree'
alias tree2='eza --icons --tree --level=2'
alias tree3='eza --icons --tree --level=3'

alias cp="cp -iv"
alias mv="mv -iv"
alias mkdir="mkdir -pv"

alias sloc='tokei --sort code'
alias reload='exec zsh -l'

mk () {
	mkdir -p "$1" && cd "$1";
}


# =========================================================
# Navigation
# =========================================================

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'

alias -- -='cd -'


# =========================================================
# Git
# =========================================================

alias gaa='git add --all'
alias gclean='git clean --interactive -d'
alias gd='git diff'
alias glog='git log --oneline --decorate --graph'
alias gs='git status'
alias gss='git status --short'

gpb () {
	local branch
	branch=$(git symbolic-ref --quiet --short HEAD) || return
	git push --force-with-lease origin "$branch"
}
