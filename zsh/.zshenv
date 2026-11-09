# Location of this repo
export DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

export LANG="${LANG:-en_US.UTF-8}"
export EDITOR=nvim

# bat and delta use the terminal's 16-colour palette (Ghostty jellybeans-hc)
export BAT_THEME="${BAT_THEME:-ansi}"

# ripgrep searches hidden files (stow packages use dot-names); set here so Neovim and non-interactive shells get it
export RIPGREP_CONFIG_PATH="${RIPGREP_CONFIG_PATH:-$HOME/.config/ripgrep/rc}"

# lazygit reads one config on macOS and Linux (its macOS default is ~/Library/Application Support)
export LG_CONFIG_FILE="${LG_CONFIG_FILE:-$HOME/.config/lazygit/config.yml}"

# Put user-local binaries first on PATH (no duplicates)
typeset -U path
path=("$HOME/.local/bin" $path)

# mise shims: mise tools for non-interactive shells (scripts, ssh commands, agents); .zshrc activates mise fully
path=("$HOME/.local/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" $path)

# Rust toolchain
[[ -r $HOME/.cargo/env ]] && source "$HOME/.cargo/env"
