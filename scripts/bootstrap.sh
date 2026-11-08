#!/usr/bin/env bash
# Clone (or update) the dotfiles repo, then run install.sh with the given flags.
# Usage: curl -fsSL https://raw.githubusercontent.com/hhoikoo/dotfiles/main/scripts/bootstrap.sh | bash -s -- [flags]
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
DOTFILES_REF="${DOTFILES_REF:-main}"
REPO_HTTPS="https://github.com/hhoikoo/dotfiles.git"
REPO_SSH="git@github.com:hhoikoo/dotfiles.git"

if ! command -v git >/dev/null 2>&1; then
  if [[ $(uname -s) == Linux ]]; then
    sudo apt-get update
    sudo apt-get install -y git
  else
    echo "git is required; install the Xcode command line tools: xcode-select --install" >&2
    exit 1
  fi
fi

if [[ -d $DOTFILES/.git ]]; then
  git -C "$DOTFILES" pull --ff-only
else
  git clone --branch "$DOTFILES_REF" "$REPO_HTTPS" "$DOTFILES"
fi

# Read over HTTPS, push over SSH
git -C "$DOTFILES" remote set-url --push origin "$REPO_SSH"

export DOTFILES
exec "$DOTFILES/scripts/install.sh" "$@"
