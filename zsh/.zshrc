# History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space

# Emacs keymap; free Ctrl-S for forward history search
bindkey -e
unsetopt flowcontrol

# Plugin bundle: regenerate the static file when the list changes or the file is empty
zsh_plugins=${ZDOTDIR:-$HOME}/.zsh_plugins
if [[ ! -s ${zsh_plugins}.zsh || ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  if [[ -r ${ZDOTDIR:-$HOME}/.antidote/antidote.zsh ]]; then
    (
      source ${ZDOTDIR:-$HOME}/.antidote/antidote.zsh
      antidote bundle <${zsh_plugins}.txt >${zsh_plugins}.zsh
    )
  else
    print -u2 "antidote missing: run ~/.dotfiles/scripts/install.sh"
  fi
fi

# Completion: zsh-completions goes on fpath before compinit; fzf-tab loads after it
fpath=(${XDG_CACHE_HOME:-$HOME/.cache}/antidote/github.com/zsh-users/zsh-completions/src $fpath)
autoload -Uz compinit
_zcd=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump
[[ -d ${_zcd:h} ]] || mkdir -p ${_zcd:h}
if [[ -n $_zcd(#qN.mh+24) || ! -f $_zcd ]]; then compinit -d $_zcd; else compinit -C -d $_zcd; fi
unset _zcd

# Load plugins
[[ -r ${zsh_plugins}.zsh ]] && source ${zsh_plugins}.zsh

# History substring search on up/down arrows
bindkey "^[[A" history-substring-search-up
bindkey "^[[B" history-substring-search-down
[[ -n $terminfo[kcuu1] ]] && bindkey "$terminfo[kcuu1]" history-substring-search-up
[[ -n $terminfo[kcud1] ]] && bindkey "$terminfo[kcud1]" history-substring-search-down

# Tool integrations
eval "$(mise activate zsh)"
# fzf walks with fd (global ignore list in ~/.config/fd/ignore) instead of its built-in walker
export FZF_CTRL_T_COMMAND='fd --type f --type d --hidden --follow --exclude .git'
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
# fzf key bindings need a terminal on stdin
[[ -t 0 ]] && source <(fzf --zsh)
eval "$(zoxide init zsh --cmd cd)"

# Render man pages through bat
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# Aliases
alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -la --git --group-directories-first --icons=auto'
alias lt='eza --tree --level=2 --icons=auto'
alias cat='bat --paging=never --style=plain'
alias top=btop
alias vim=nvim
alias vi=nvim
alias lg=lazygit
alias tm='tmux new-session -A -s main'

# macOS only: point gcc/g++ at the newest Homebrew GCC
if [[ $OSTYPE == darwin* ]]; then
  _brew_gcc=( /opt/homebrew/bin/gcc-<->(N) )
  if (( ${#_brew_gcc} )); then
    _brew_gcc=( ${(on)_brew_gcc} )
    alias gcc="${_brew_gcc[-1]:t}"
    alias g++="g++-${_brew_gcc[-1]:t:s/gcc-//}"
  fi
  unset _brew_gcc
fi

# Per-machine settings, not in the repo (optional)
[[ -r ~/.config/zsh/local.zsh ]] && source ~/.config/zsh/local.zsh

# Prompt
eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh/config.omp.json)"
