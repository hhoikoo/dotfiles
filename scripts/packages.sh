#!/usr/bin/env bash
# Print the stow packages for this OS, one per line.
# Usage: scripts/packages.sh
set -euo pipefail

printf '%s\n' zsh tmux git mise ohmyposh nvim fd bin claude codex
[[ $(uname -s) == Darwin ]] && printf '%s\n' ghostty
exit 0
