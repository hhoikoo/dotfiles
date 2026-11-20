#!/usr/bin/env bash
# Keep repos out of the kb: add each repo's slug to KB_EXCLUDE in the host config and write
# autoMemoryEnabled false into the repo's .claude/settings.local.json, so built-in memory
# is off there. kb-sync refuses notes under projects/<slug>/ for every slug in KB_EXCLUDE.
# Usage: scripts/kb-exclude.sh <repo-dir>...
set -euo pipefail

HOST_ENV="${KB_HOST_ENV:-$HOME/.config/dotfiles/host.env}"
[[ $# -gt 0 ]] || { echo "usage: kb-exclude.sh <repo-dir>..." >&2; exit 2; }

log() { printf '%-5s %s\n' "$1" "$2"; }

host_get() {
  [[ -f $HOST_ENV ]] || return 0
  sed -n "s/^$1=//p" "$HOST_ENV" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

for dir in "$@"; do
  [[ -d $dir ]] || { echo "kb-exclude: not a directory: $dir" >&2; exit 1; }
  dir="$(cd "$dir" && pwd -P)"
  url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  slug="$(basename "${url:-$dir}" .git)"
  slug="${slug##*:}"

  current="$(host_get KB_EXCLUDE | tr ',' ' ')"
  if [[ " $current " == *" $slug "* ]]; then
    log ok "$slug already in KB_EXCLUDE"
  else
    mkdir -p "$(dirname "$HOST_ENV")"
    tmp="$(mktemp)"
    { [[ -f $HOST_ENV ]] && grep -v '^KB_EXCLUDE=' "$HOST_ENV" || true; } >"$tmp"
    printf 'KB_EXCLUDE="%s"\n' "$(echo "$current $slug" | xargs)" >>"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$HOST_ENV"
    log "done" "$slug added to KB_EXCLUDE"
  fi

  mkdir -p "$dir/.claude"
  file="$dir/.claude/settings.local.json"
  [[ -s $file ]] || echo '{}' >"$file"
  tmp="$(mktemp)"
  jq '.autoMemoryEnabled = false' "$file" >"$tmp"
  if cmp -s "$tmp" "$file"; then rm -f "$tmp"; log ok "$file"; else mv "$tmp" "$file"; log "done" "$file: autoMemoryEnabled false"; fi

  # Keep the local settings out of commits
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$dir" check-ignore -q .claude/settings.local.json; then
    exclude="$(git -C "$dir" rev-parse --path-format=absolute --git-path info/exclude)"
    mkdir -p "$(dirname "$exclude")"
    echo '.claude/settings.local.json' >>"$exclude"
    log "done" "ignored locally via $exclude"
  fi
done
