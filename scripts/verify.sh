#!/usr/bin/env bash
# Read-only checks that the install is healthy. Exits non-zero on any failure.
# Usage: scripts/verify.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOTFILES="${DOTFILES:-$REPO}"
OS="$(uname -s)"
fail=0

pass() { printf 'ok    %s\n' "$1"; }
warn() { printf 'warn  %s\n' "$1"; }
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

# 7. macOS: Touch ID for sudo, including inside tmux
if [[ $OS == Darwin ]]; then
  if grep -q pam_reattach /etc/pam.d/sudo_local 2>/dev/null && grep -Eq '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo_local; then
    pass "Touch ID for sudo (pam_reattach + pam_tid)"
  else
    bad "Touch ID for sudo is not set up; run make link"
  fi
fi

# 8. Git filter that keeps per-machine Claude settings out of commits
if [[ $(git -C "$REPO" config --get filter.claude-settings.clean 2>/dev/null) == "scripts/settings-filter.sh clean" ]]; then
  pass "git filter claude-settings"
else
  bad "git filter claude-settings missing; run make link"
fi

# 9. Commit signing (commit.gpgsign: true = on, false = declined, unset = undecided)
sign="$(git config --includes --type=bool commit.gpgsign 2>/dev/null || true)"
if [[ $sign == true ]]; then
  key="$(git config --includes user.signingkey 2>/dev/null || true)"
  pub="${key#key::}"
  keyfile=""
  if [[ $pub == "$key" && -f ${key%.pub}.pub ]]; then
    keyfile="$key"
    pub="$(awk '{print $1" "$2}' "${key%.pub}.pub")"
  fi
  signers="$(git config --includes gpg.ssh.allowedSignersFile 2>/dev/null || true)"
  signers="${signers/#\~/$HOME}"
  if [[ -z $key || $pub == "$key" ]]; then
    bad "commit signing: user.signingkey is neither a key:: value nor a key file"
  elif [[ -z $signers || ! -f $signers ]] || ! grep -qF "$pub" "$signers"; then
    bad "commit signing: allowed_signers is missing or lacks the signing key; run make link"
  elif [[ -n $keyfile ]]; then
    pass "commit signing: key file $keyfile in allowed_signers"
  elif (ssh-add -L 2>/dev/null || true) | grep -qF "$pub"; then
    pass "commit signing: key in allowed_signers and loaded in ssh-agent"
  else
    warn "commit signing: key not loaded in ssh-agent (launchd agent starts empty; run ssh once or open a new login shell)"
  fi
elif [[ $sign == false ]]; then
  pass "signing declined"
else
  warn "commit signing undecided; run GIT_SIGN=1 make install (or install.sh)"
fi

# 9b. Git tuning, SSH connection sharing and background maintenance
tuning_ok=1
for kv in fetch.prune=true fetch.parallel=0 rebase.autostash=true push.autosetupremote=true; do
  [[ $(git config --get "${kv%%=*}" 2>/dev/null) == "${kv#*=}" ]] || { tuning_ok=0; bad "git ${kv%%=*} is not ${kv#*=}; run make link"; }
done
(( tuning_ok )) && pass "git tuning: fetch.prune, fetch.parallel, rebase.autoStash, push.autoSetupRemote"
if [[ $(head -n 1 "$HOME/.ssh/config" 2>/dev/null) == 'Include ~/.ssh/config.d/*' ]] && [[ -f $HOME/.ssh/config.d/github.conf ]]; then
  pass "ssh: Include first in ~/.ssh/config, github.conf installed"
else
  bad "ssh: ~/.ssh/config lacks the Include first line or github.conf is missing; run make ssh"
fi
if [[ -n $(git config --file "$HOME/.config/git/config" --get-all maintenance.repo 2>/dev/null) ]]; then
  bad "git maintenance: tracked ~/.config/git/config has maintenance.repo lines"
elif [[ -n $(git config --get-all maintenance.repo 2>/dev/null) ]]; then
  pass "git maintenance: $(git config --get-all maintenance.repo | wc -l | tr -d ' ') repos registered via the local file"
else
  bad "git maintenance: no repos registered; run make git-maintenance"
fi

# 10. Herdr: the app on desktops, herdr-core everywhere it is installed
herdr_mode="$("$REPO/scripts/herdr-mode.sh" 2>/dev/null || echo none)"
if [[ $herdr_mode == app ]]; then
  if [[ -d $HOME/Applications/Herdr.app || -d /Applications/Herdr.app || -x ${XDG_DATA_HOME:-$HOME/.local/share}/herdr-app/herdr-app ]]; then
    pass "herdr app installed"
  else
    bad "herdr app missing; run make install"
  fi
fi
if [[ $herdr_mode != none ]]; then
  if v="$("$HOME/.local/bin/herdr-core" --version 2>/dev/null)"; then
    pass "herdr-core: $v"
  else
    bad "herdr-core missing or broken; run make install"
  fi
fi
# Without lingering, herdr-core and its programs stop when the last login closes
if [[ $herdr_mode == core ]] && have_linger="$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)"; then
  if [[ $have_linger == yes ]]; then
    pass "linger on: herdr-core keeps running after logout"
  else
    warn "linger off: herdr-core stops at logout (sudo loginctl enable-linger $USER)"
  fi
fi

# 11. Knowledge base: only when this host has a role in the host config
host_env="${KB_HOST_ENV:-$HOME/.config/dotfiles/host.env}"
hget() { sed -n "s/^$1=//p" "$host_env" 2>/dev/null | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }
kb_role="$(hget KB_ROLE)"
if [[ -z $kb_role ]]; then
  pass "kb: none on this host"
else
  kb="$HOME/.kb"
  overlay="${CLAUDE_SETTINGS_OVERLAY:-$HOME/.config/claude/local.json}"
  kb_remote="$(hget KB_REMOTE)"
  if [[ ! -d $kb/.git ]]; then
    bad "kb: $kb is missing or not a git clone; run make kb"
  elif [[ $(git -C "$kb" remote get-url origin 2>/dev/null) != "$kb_remote" ]]; then
    bad "kb: origin of $kb is not $kb_remote"
  else
    pass "kb ($kb_role): clone with origin $kb_remote"
  fi
  if [[ $(jq -r '.autoMemoryDirectory // ""' "$overlay" 2>/dev/null) == "$kb" ]] \
    && jq -e '(.hooks.SessionStart // []) + (.hooks.SessionEnd // []) | map(.hooks[].command) | map(test("kb-sync")) | any' "$overlay" >/dev/null 2>&1; then
    pass "kb: autoMemoryDirectory and hooks set in $overlay"
  else
    bad "kb: autoMemoryDirectory or hooks missing from $overlay; run make kb"
  fi
  if [[ $(jq -r '.autoDreamEnabled' "$overlay" 2>/dev/null) == false ]]; then
    pass "kb: autoDreamEnabled false"
  else
    bad "kb: autoDreamEnabled is not false in $overlay"
  fi
  if [[ $kb_role == work ]]; then
    # A work host must hold nothing of the personal kb: remote, folder or history
    leaks=""
    [[ $kb_remote == *kb-work || $kb_remote == *kb-work.git ]] || leaks+=" remote-config-not-kb-work"
    [[ -d $kb/.git ]] && [[ $(git -C "$kb" remote | grep -vc '^origin$') -eq 0 ]] || leaks+=" extra-git-remote"
    [[ -d $kb/.git ]] && git -C "$kb" remote -v | grep -q 'kb-personal' && leaks+=" personal-remote"
    [[ -d $kb/.git ]] && git -C "$kb" for-each-ref --format='%(refname)' | grep -qv -e '^refs/heads/main$' -e '^refs/remotes/origin/' && leaks+=" foreign-refs"
    for p in "$HOME/.kb-personal" "$HOME/kb-personal" "$HOME/.kb.personal"; do [[ -e $p ]] && leaks+=" $p"; done
    if [[ -z $leaks ]]; then
      pass "kb isolation: no personal remote, folder or refs on this work host"
    else
      bad "kb isolation:$leaks"
    fi
  fi
  if [[ -d $kb/.git ]]; then
    if lint_out="$("$REPO/bin/.local/bin/kb-lint" "$kb" 2>&1)"; then
      pass "$(tail -n 1 <<<"$lint_out")"
    else
      warn "kb-lint found errors in $kb (run kb-lint)"
    fi
  fi
fi

exit "$fail"
