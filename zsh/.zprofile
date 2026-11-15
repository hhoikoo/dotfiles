# macOS only: Homebrew and related PATH entries (path_helper reorders PATH after .zshenv)
if [[ $OSTYPE == darwin* ]]; then
  # Static copy of `brew shellenv` (saves a ~15 ms fork on every login shell)
  export HOMEBREW_PREFIX="/opt/homebrew"
  export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
  export HOMEBREW_REPOSITORY="/opt/homebrew"
  fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
  export FPATH
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
  [ -z "${MANPATH-}" ] || { export MANPATH="${MANPATH%"${MANPATH##*[!:]}"}"; export MANPATH=":${MANPATH#"${MANPATH%%[!:]*}"}"; }
  export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
  path=(
    /opt/homebrew/opt/curl/bin
    /opt/homebrew/opt/make/libexec/gnubin
    "$HOME/.opencode/bin"
    $path
  )
  source ~/.orbstack/shell/init.zsh 2>/dev/null || :
  # Replace a missing, dead or ~/.ssh/agent SSH_AUTH_SOCK (stale values leak in from VS Code terminals via tmux) with the launchd agent socket
  if [[ ! -S ${SSH_AUTH_SOCK-} || $SSH_AUTH_SOCK == "$HOME"/.ssh/agent/* ]]; then
    launchd_ssh_sock=$(launchctl print "gui/$UID/com.openssh.ssh-agent" 2>/dev/null | awk '/SSH_AUTH_SOCK =>/{print $3}')
    [[ -S $launchd_ssh_sock ]] && export SSH_AUTH_SOCK=$launchd_ssh_sock
    unset launchd_ssh_sock
  fi
  # Load SSH keys from the keychain when the launchd agent is running but empty
  ssh-add -l >/dev/null 2>&1
  (( $? == 1 )) && ssh-add --apple-load-keychain -q 2>/dev/null
fi

# Keep user-local binaries first
typeset -U path
path=("$HOME/.local/bin" $path)
