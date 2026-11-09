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
  # Load SSH keys from the keychain when the launchd agent is running but empty
  ssh-add -l >/dev/null 2>&1
  (( $? == 1 )) && ssh-add --apple-load-keychain -q 2>/dev/null
fi

# Keep user-local binaries first
typeset -U path
path=("$HOME/.local/bin" $path)
