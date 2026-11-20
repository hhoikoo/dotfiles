#!/usr/bin/env bash
# Register ~/.kb and the git repos under ~/Developer (depth 2) for background git maintenance, then start the scheduler (launchd on macOS, systemd user timers on Linux). Idempotent.
# Registration goes to the untracked ~/.config/git/local, never to the tracked ~/.config/git/config.
# Usage: scripts/git-maintenance.sh
set -euo pipefail

LOCAL="$HOME/.config/git/local"
DEV="${DEVELOPER_DIR_ROOT:-$HOME/Developer}"

log() { printf '%-5s %s\n' "$1" "$2"; }

command -v git >/dev/null || { echo "git is missing" >&2; exit 1; }
mkdir -p "$(dirname "$LOCAL")"
touch "$LOCAL"
# Resolve the link so the real file is the one that gets written
LOCAL="$(cd "$(dirname "$LOCAL")" && pwd -P)/$(basename "$LOCAL")"

repos=()
[[ -d $HOME/.kb/.git ]] && repos+=("$HOME/.kb")
if [[ -d $DEV ]]; then
  # A main repo has a .git directory; a worktree has a .git file, so it is skipped. Repos at depth 2 have .git at depth 3.
  while IFS= read -r g; do repos+=("${g%/.git}"); done < <(
    find "$DEV" -maxdepth 3 \( -name .claude -o -name node_modules \) -prune -o -name .git -type d -print | sort
  )
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

# start must run inside a repository and registers it in the global config; pointing the global config at the local file keeps the tracked one clean
if (( ${#repos[@]} == 0 )); then
  echo "no repositories found to maintain" >&2
  exit 1
fi
(cd "${repos[0]}" && GIT_CONFIG_GLOBAL="$LOCAL" git maintenance start)
log "done" "scheduler started"

# The tracked file is what ~/.config/git/config resolves to
if [[ -n $(git config --file "$HOME/.config/git/config" --get-all maintenance.repo 2>/dev/null) ]]; then
  echo "tracked git config has maintenance.repo lines" >&2
  exit 1
fi
