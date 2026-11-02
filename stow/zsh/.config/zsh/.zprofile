# Login shell: OS-specific environment. These paths differ per platform, so
# they can't be committed as literal values.

case "$(uname -s)" in
  Darwin)
    [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    export PNPM_HOME="$HOME/Library/pnpm"
    ;;
  Linux)
    [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
    export PNPM_HOME="$HOME/.local/share/pnpm"
    ;;
esac

[[ -n "${PNPM_HOME:-}" ]] && path=("$PNPM_HOME/bin" $path)
