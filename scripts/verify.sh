#!/usr/bin/env bash
# Read-only checks that the install is healthy. Exits non-zero on any failure.
# Usage: scripts/verify.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOTFILES="${DOTFILES:-$REPO}"
OS="$(uname -s)"
fail=0

pass() { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=1; }

# Which owner provides each path: mise installs and shims count as one owner
owner() {
  case $1 in
    */mise/installs/* | */mise/shims/*) echo mise ;;
    *) echo "$1" ;;
  esac
}

# 1. Every tool resolves to exactly one source (checked from an interactive zsh)
for tool in node pnpm python3 nvim gh bat fd mise; do
  paths=()
  while IFS= read -r p; do paths+=("$p"); done < <(zsh -i -c "whence -ap $tool" 2>/dev/null)
  owners=()
  for p in ${paths[@]+"${paths[@]}"}; do
    # OS and Homebrew-dependency interpreters are not competing installs
    [[ $tool == python3 && ( $p == /usr/bin/python3 || $p == /bin/python3 || $p == /opt/homebrew/bin/python3 ) ]] && continue
    owners+=("$(owner "$p")")
  done
  n="$(printf '%s\n' "${owners[@]:-}" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
  if [[ $n == 1 ]]; then
    pass "$tool: ${paths[0]}"
  else
    bad "$tool: $n sources (${paths[*]:-none})"
  fi
done

# 2. Login shell
login_shell="$(if [[ $OS == Darwin ]]; then dscl . -read "/Users/$USER" UserShell | awk '{print $2}'; else getent passwd "$USER" | cut -d: -f7; fi)"
if [[ ${SHELL:-} == */zsh ]]; then
  pass "\$SHELL is $SHELL"
elif [[ $login_shell == */zsh ]]; then
  pass "login shell is $login_shell (reconnect to refresh \$SHELL)"
else
  bad "shell is ${SHELL:-unset}, expected zsh"
fi

# 3. Stowed files point into the repo
pkgs=()
while IFS= read -r p; do pkgs+=("$p"); done < <("$REPO/scripts/packages.sh")
links=0
for pkg in "${pkgs[@]}"; do
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO/$pkg/"}"
    resolved="$(readlink -f "$HOME/$rel" 2>/dev/null || true)"
    if [[ $resolved == "$DOTFILES"/* || $resolved == "$REPO"/* ]]; then
      links=$((links + 1))
    else
      bad "$HOME/$rel does not resolve into $DOTFILES"
    fi
  done < <(find "$REPO/$pkg" \( -type f -o -type l \) -print0)
done
pass "$links stowed files resolve into the repo"

# 4. Interactive zsh starts silently
errs="$(zsh -i -c exit 2>&1 >/dev/null)"
if [[ -z $errs ]]; then
  pass "zsh -i -c exit: no stderr"
else
  bad "zsh -i -c exit wrote to stderr: $errs"
fi

# 5. zsh plugins are loaded
missing=""
widgets="$(zsh -i -c 'zle -l' 2>/dev/null)"
for w in history-substring-search-up autosuggest-accept fzf-tab-complete; do
  grep -q "^$w" <<<"$widgets" || missing+=" $w"
done
if [[ -z $missing ]]; then
  pass "zsh plugins loaded"
else
  bad "zsh plugin widgets missing:$missing"
fi

# 6. Startup time
ms="$(perl -MTime::HiRes=time -e '$t=time; system("zsh -i -c exit >/dev/null 2>&1"); printf "%d", (time-$t)*1000')"
pass "zsh startup: ${ms} ms"

exit "$fail"
