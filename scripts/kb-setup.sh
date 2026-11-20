#!/usr/bin/env bash
# Set up this host's kb: record the role, clone the repo, build the index, and write the
# kb settings (autoMemoryDirectory, SessionStart and SessionEnd hooks, autoDreamEnabled false)
# into the untracked Claude settings overlay. Called by install.sh; also runnable alone (make kb).
# Usage: scripts/kb-setup.sh [personal|work]
# Environment:
#   KB            role, when no argument is given; unset reuses the role recorded in the host config
#   KB_REMOTE     remote override (default git@github.com:hhoikoo/kb-<role>.git)
#   KB_HOST_ENV   host config (default ~/.config/dotfiles/host.env)
#   CLAUDE_SETTINGS_OVERLAY, CLAUDE_SETTINGS_FILE   overlay and working settings file
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOST_ENV="${KB_HOST_ENV:-$HOME/.config/dotfiles/host.env}"
OVERLAY="${CLAUDE_SETTINGS_OVERLAY:-$HOME/.config/claude/local.json}"
SETTINGS="${CLAUDE_SETTINGS_FILE:-$REPO/claude/.claude/settings.json}"
KB_PATH="$HOME/.kb"
BIN="$HOME/.local/bin"

log()  { printf '%-5s %s\n' "$1" "$2"; }
warn() { printf 'warn  %s\n' "$1" >&2; }

host_get() {
  [[ -f $HOST_ENV ]] || return 0
  sed -n "s/^$1=//p" "$HOST_ENV" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

host_set() { # host_set KEY VALUE: replace the line or append it
  local tmp
  mkdir -p "$(dirname "$HOST_ENV")"
  tmp="$(mktemp)"
  { [[ -f $HOST_ENV ]] && grep -v "^$1=" "$HOST_ENV" || true; } >"$tmp"
  printf '%s=%s\n' "$1" "$2" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$HOST_ENV"
}

role="${1:-${KB:-}}"
recorded="$(host_get KB_ROLE)"
if [[ -z $role ]]; then
  role="$recorded"
fi
if [[ -z $role ]]; then
  log skip "kb (KB unset and no role recorded)"
  exit 0
fi
case $role in
  personal | work) ;;
  *) echo "kb-setup: KB must be personal or work, not '$role'" >&2; exit 2 ;;
esac
if [[ -n $recorded && $recorded != "$role" ]]; then
  echo "kb-setup: this host is recorded as $recorded; refusing to switch to $role (edit $HOST_ENV by hand if that is intended)" >&2
  exit 1
fi

remote="${KB_REMOTE:-$(host_get KB_REMOTE)}"
[[ -n $remote ]] || remote="git@github.com:hhoikoo/kb-$role.git"
if [[ $role == work && $remote != *kb-work && $remote != *kb-work.git ]]; then
  echo "kb-setup: a work host must use the kb-work remote, not $remote" >&2
  exit 1
fi
if [[ $role == personal && $remote == *kb-work* ]]; then
  echo "kb-setup: a personal host must not use the kb-work remote" >&2
  exit 1
fi

if [[ $recorded == "$role" && $(host_get KB_REMOTE) == "$remote" ]]; then
  log ok "host config $HOST_ENV"
else
  host_set KB_ROLE "$role"
  host_set KB_REMOTE "$remote"
  log "done" "host config: role $role"
fi

# Clone first; settings are written only after the clone works
if [[ -d $KB_PATH/.git ]]; then
  log skip "kb clone $KB_PATH"
elif [[ -e $KB_PATH || -L $KB_PATH ]]; then
  echo "kb-setup: $KB_PATH exists but is not a git clone; move it aside and run again" >&2
  exit 1
elif git clone -q "$remote" "$KB_PATH"; then
  log "done" "kb cloned to $KB_PATH"
else
  echo "kb-setup: clone of $remote failed; settings not written" >&2
  exit 1
fi
if [[ $(git -C "$KB_PATH" remote get-url origin 2>/dev/null) != "$remote" ]]; then
  warn "origin of $KB_PATH is not $remote"
fi

"$REPO/bin/.local/bin/kb-index" "$KB_PATH"
log ok "kb index built"

mkdir -p "$(dirname "$OVERLAY")"
[[ -s $OVERLAY ]] || echo '{}' >"$OVERLAY"
tmp="$(mktemp)"
jq --arg dir "$KB_PATH" --arg cmd "$BIN/kb-sync" '
  def drop: map(select(((.hooks // []) | map((.command // "") | test("kb-sync")) | any) | not));
  def hook($arg): {hooks: [{type: "command", command: ($cmd + " " + $arg), timeout: 90}]};
  .autoMemoryDirectory = $dir
  | .autoDreamEnabled = false
  | .hooks.SessionStart = (((.hooks.SessionStart // []) | drop) + [hook("start")])
  | .hooks.SessionEnd = (((.hooks.SessionEnd // []) | drop) + [hook("end")])
' "$OVERLAY" >"$tmp"
if cmp -s "$tmp" "$OVERLAY"; then
  rm -f "$tmp"
  log ok "kb settings in $OVERLAY"
else
  mv "$tmp" "$OVERLAY"
  log "done" "kb settings written to $OVERLAY"
fi

# The working settings file keeps the overlay merged in (see settings-filter.sh)
if [[ -f $SETTINGS ]]; then
  tmp="$(mktemp)"
  CLAUDE_SETTINGS_OVERLAY="$OVERLAY" "$REPO/scripts/settings-filter.sh" smudge <"$SETTINGS" >"$tmp"
  if cmp -s "$tmp" "$SETTINGS"; then rm -f "$tmp"; else cat "$tmp" >"$SETTINGS"; rm -f "$tmp"; log "done" "merged overlay into $SETTINGS"; fi
fi
