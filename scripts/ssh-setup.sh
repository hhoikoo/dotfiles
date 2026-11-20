#!/usr/bin/env bash
# Install ssh/github.conf into ~/.ssh/config.d and make ~/.ssh/config include that directory first. Idempotent; never prints the contents of ~/.ssh/config.
# Usage: scripts/ssh-setup.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SSH_DIR="$HOME/.ssh"
CONFIG="$SSH_DIR/config"
INCLUDE='Include ~/.ssh/config.d/*'

log() { printf '%-5s %s\n' "$1" "$2"; }

umask 077
mkdir -p "$SSH_DIR" "$SSH_DIR/config.d"
chmod 700 "$SSH_DIR"

# A copy, not a link: ~/.ssh must not depend on where the repo checkout is
if cmp -s "$REPO/ssh/github.conf" "$SSH_DIR/config.d/github.conf"; then
  log skip "$HOME/.ssh/config.d/github.conf up to date"
else
  install -m 644 "$REPO/ssh/github.conf" "$SSH_DIR/config.d/github.conf"
  log "done" "$HOME/.ssh/config.d/github.conf installed"
fi

# Include must come first: ssh uses the first value it finds for each option
if [[ ! -e $CONFIG ]]; then
  printf '%s\n' "$INCLUDE" >"$CONFIG"
  chmod 600 "$CONFIG"
  log "done" "$HOME/.ssh/config created with the Include line"
elif [[ $(head -n 1 "$CONFIG") == "$INCLUDE" ]]; then
  log skip "ssh config already starts with the Include line"
else
  tmp="$(mktemp "$SSH_DIR/config.XXXXXX")"
  trap 'rm -f "${tmp:?}"' EXIT
  { printf '%s\n' "$INCLUDE"; cat "$CONFIG"; } >"$tmp"
  # Keep the original mode (the new file starts at 600 from umask 077)
  chmod "$(stat -c '%a' "$CONFIG" 2>/dev/null || stat -f '%Lp' "$CONFIG")" "$tmp"
  mv "$tmp" "$CONFIG"
  trap - EXIT
  log "done" "Include line added at the top of ~/.ssh/config"
fi
