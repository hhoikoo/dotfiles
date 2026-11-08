# macOS only: Homebrew and related PATH entries (path_helper reorders PATH after .zshenv)
if [[ $OSTYPE == darwin* ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  path=(
    /opt/homebrew/opt/curl/bin
    /opt/homebrew/opt/make/libexec/gnubin
    "$HOME/.opencode/bin"
    $path
  )
  source ~/.orbstack/shell/init.zsh 2>/dev/null || :
fi

# Keep user-local binaries first
typeset -U path
path=("$HOME/.local/bin" $path)
