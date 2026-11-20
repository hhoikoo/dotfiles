#!/usr/bin/env bash
# Register ~/.kb and the git repos under this host's repo folders (depth 2) for background git maintenance, then start the scheduler (launchd on macOS, systemd user timers on Linux). Idempotent.
# Registration goes to the untracked ~/.config/git/local, never to the tracked ~/.config/git/config.
# The folders are a colon separated list: GIT_MAINTENANCE_DIRS in the environment, else in ~/.config/dotfiles/host.env, else ~/Developer.
# On Linux a systemd drop-in reruns this script with --register-only before every scheduled run, so repos cloned later are picked up.
# Usage: scripts/git-maintenance.sh [--register-only]
set -euo pipefail

LOCAL="$HOME/.config/git/local"
HOST_ENV="${KB_HOST_ENV:-$HOME/.config/dotfiles/host.env}"
REGISTER_ONLY=0
[[ ${1:-} == --register-only ]] && REGISTER_ONLY=1

dirs="${GIT_MAINTENANCE_DIRS:-}"
if [[ -z $dirs && -f $HOST_ENV ]]; then
  dirs="$(sed -n 's/^GIT_MAINTENANCE_DIRS=//p' "$HOST_ENV" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
fi
dirs="${dirs:-$HOME/Developer}"

log() { printf '%-5s %s\n' "$1" "$2"; }

command -v git >/dev/null || { echo "git is missing" >&2; exit 1; }
mkdir -p "$(dirname "$LOCAL")"
touch "$LOCAL"
# Resolve the link so the real file is the one that gets written
LOCAL="$(cd "$(dirname "$LOCAL")" && pwd -P)/$(basename "$LOCAL")"

repos=()
[[ -d $HOME/.kb/.git ]] && repos+=("$HOME/.kb")
IFS=: read -ra roots <<<"$dirs"
for root in "${roots[@]}"; do
  [[ -n $root ]] || continue
  # A leading ~ is expanded here, since a value read from host.env is not expanded by the shell
  # shellcheck disable=SC2088 # the tilde is matched literally
  case "$root" in "~") root="$HOME" ;; "~/"*) root="$HOME/${root#"~/"}" ;; esac
  if [[ ! -d $root ]]; then
    log skip "$root does not exist"
    continue
  fi
  # A main repo has a .git directory; a worktree has a .git file, so it is skipped. Repos at depth 2 have .git at depth 3.
  while IFS= read -r g; do repos+=("${g%/.git}"); done < <(
    find "$root" -maxdepth 3 \( -name .claude -o -name node_modules \) -prune -o -name .git -type d -print | sort
  )
done

# bash 3.2 treats an empty array as unbound under set -u, so test the count before expanding it
if (( ${#repos[@]} == 0 )); then
  echo "no repositories found to maintain" >&2
  exit 1
fi

for r in "${repos[@]}"; do
  # A stray .git directory that is not a repository (for example an empty one) is skipped
  if ! git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
    log skip "$r is not a git repository"
    continue
  fi
  if git config --file "$LOCAL" --get-all maintenance.repo | grep -qxF "$r"; then
    log skip "$r"
  else
    git -C "$r" maintenance register --config-file "$LOCAL"
    log "done" "registered $r"
  fi
done

if (( REGISTER_ONLY )); then
  exit 0
fi

# start must run inside a repository and registers it in the global config; pointing the global config at the local file keeps the tracked one clean
(cd "${repos[0]}" && GIT_CONFIG_GLOBAL="$LOCAL" git maintenance start)
log "done" "scheduler started"

# git maintenance start rewrites the units but leaves drop-ins alone; the drop-in rescans the folders before each scheduled run
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ $(uname) == Linux && $script_dir == */.claude/worktrees/* ]]; then
  log warn "run from a worktree ($script_dir); rescan drop-in not installed"
elif [[ $(uname) == Linux ]]; then
  dropin="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/git-maintenance@.service.d"
  mkdir -p "$dropin"
  printf '[Service]\nExecStartPre=-"%s" --register-only\n' "$script_dir/git-maintenance.sh" >"$dropin/rescan.conf"
  systemctl --user daemon-reload 2>/dev/null || true
  log "done" "rescan drop-in $dropin/rescan.conf"
fi

# The tracked file is what ~/.config/git/config resolves to
if [[ -n $(git config --file "$HOME/.config/git/config" --get-all maintenance.repo 2>/dev/null) ]]; then
  echo "tracked git config has maintenance.repo lines" >&2
  exit 1
fi
