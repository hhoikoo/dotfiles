#!/usr/bin/env bash
# Install packages and tools, stow the dotfiles, and verify the result.
# Usage: scripts/install.sh [--no-packages] [-h]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [--no-packages] [-h]

  --no-packages   Skip steps 2-4 (system packages, shims, official installers)
  -h              Show this help

Environment:
  DOTFILES    Repo location (default: ~/.dotfiles)
  GIT_NAME    Git user.name for ~/.config/git/local
  GIT_EMAIL   Git user.email for ~/.config/git/local
  GIT_SIGN    1 to set up SSH commit signing, 0 to skip it
EOF
}

NO_PACKAGES=0
for arg in "$@"; do
  case $arg in
    --no-packages) NO_PACKAGES=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OS="$(uname -s)"
TS="$(date +%Y%m%d-%H%M%S)"

log()  { printf '%-5s %s\n' "$1" "$2"; }
warn() { printf 'warn  %s\n' "$1" >&2; }
step() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ -z ${DOTFILES:-} ]]; then
  DOTFILES="$HOME/.dotfiles"
fi
if [[ $REPO != "$(cd "$DOTFILES" 2>/dev/null && pwd -P || echo "$DOTFILES")" ]]; then
  warn "repo is at $REPO but DOTFILES is $DOTFILES; links will point into $REPO"
fi
export DOTFILES

if [[ $OS == Linux ]]; then
  if ! grep -qx 'ID=ubuntu' /etc/os-release 2>/dev/null; then
    warn "this script is tested on Ubuntu only"
  fi
elif [[ $OS != Darwin ]]; then
  echo "unsupported OS: $OS" >&2
  exit 1
fi

# Installers below check for ~/.local/bin on PATH before touching shell profiles
export PATH="$HOME/.local/bin:$PATH"

PKGS=()
while IFS= read -r pkg; do PKGS+=("$pkg"); done < <("$REPO/scripts/packages.sh")

# Read a prompt answer from the terminal even when stdin is a pipe
tty_usable() { ( : </dev/tty ) 2>/dev/null; }
ask() { # ask "prompt" -> sets REPLY
  printf '%s' "$1" >/dev/tty
  IFS= read -r REPLY </dev/tty || REPLY=""
}

# ---------------------------------------------------------------- 1. Preflight
step "1. Preflight"
if [[ $OS == Darwin ]]; then
  if ! have brew && [[ ! -x /opt/homebrew/bin/brew ]]; then
    echo 'Homebrew is missing. Install it, then re-run:'
    # shellcheck disable=SC2016
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  log ok "homebrew present"
else
  if sudo -n true 2>/dev/null; then
    log ok "passwordless sudo"
  else
    warn "sudo will prompt for a password"
  fi
fi

if (( NO_PACKAGES )); then
  step "2-4. Packages, shims, installers"
  log skip "--no-packages"
else
  # -------------------------------------------------------------- 2. Packages
  step "2. Packages"
  if [[ $OS == Linux ]]; then
    mapfile -t APT_PKGS < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$REPO/packages/apt.txt")
    if dpkg -s "${APT_PKGS[@]}" >/dev/null 2>&1; then
      log skip "apt packages already installed"
    else
      sudo apt-get update
      sudo apt-get install -y "${APT_PKGS[@]}"
      log "done" "apt packages installed"
    fi
  else
    if brew bundle check --file "$REPO/packages/Brewfile" >/dev/null 2>&1; then
      log skip "brew bundle satisfied"
    elif brew bundle --file "$REPO/packages/Brewfile"; then
      log "done" "brew bundle"
    else
      warn "brew bundle reported failures; continuing"
    fi
    if compgen -G "$HOME/Library/Fonts/Jetendard*" >/dev/null; then
      log skip "Jetendard font present"
    elif have gh; then
      fontdir="$(mktemp -d)"
      if gh release download -R kuskhan/jetendard -p 'Jetendard-TTF.zip' -D "$fontdir" \
        && unzip -q "$fontdir/Jetendard-TTF.zip" -d "$fontdir/x"; then
        mkdir -p "$HOME/Library/Fonts"
        find "$fontdir/x" -name '*.ttf' -exec cp {} "$HOME/Library/Fonts/" \;
        log "done" "Jetendard font installed from GitHub release"
      else
        warn "could not install the Jetendard font"
      fi
      rm -rf "$fontdir"
    else
      warn "gh is missing; cannot install the Jetendard font"
    fi
  fi

  # --------------------------------------------------------- 3. Linux shims
  step "3. Linux shims"
  if [[ $OS == Linux ]]; then
    mkdir -p "$HOME/.local/bin"
    for pair in "batcat:bat" "fdfind:fd"; do
      src="/usr/bin/${pair%%:*}"
      dst="$HOME/.local/bin/${pair##*:}"
      if [[ $(readlink "$dst" 2>/dev/null) == "$src" ]]; then
        log ok "$dst"
      else
        ln -sfn "$src" "$dst"
        log "done" "$dst -> $src"
      fi
    done
  else
    log skip "not Linux"
  fi

  # ------------------------------------------------- 4. Official installers
  step "4. Official installers"
  if have mise; then
    log skip "mise"
  else
    MISE_INSTALL_HELP=0 curl https://mise.run | sh
    # The installer may append an activation line; .zshrc already activates mise
    if [[ -f $HOME/.bashrc ]]; then
      sed -i.bak '/mise activate bash/d' "$HOME/.bashrc" && rm -f "$HOME/.bashrc.bak"
    fi
    log "done" "mise"
  fi

  if have uv; then
    log skip "uv"
  else
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
    log "done" "uv"
  fi

  if [[ $OS == Linux ]]; then
    if have oh-my-posh; then
      log skip "oh-my-posh"
    else
      curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
      log "done" "oh-my-posh"
    fi
  fi

  if [[ $OS == Linux ]]; then
    if have claude; then
      log skip "claude"
    else
      curl -fsSL https://claude.ai/install.sh | bash
      log "done" "claude"
    fi
    if have codex; then
      log skip "codex"
    else
      curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
      log "done" "codex"
    fi
  else
    have claude || echo "hint: install Claude Code: curl -fsSL https://claude.ai/install.sh | bash"
    have codex || echo "hint: install Codex: curl -fsSL https://chatgpt.com/codex/install.sh | sh"
  fi
fi

# ------------------------------------------------------------ 5. Directories
step "5. Directories"
# Pre-creating these keeps stow from replacing them with a single symlink
mkdir -p "$HOME/.config" "$HOME/.config/tmux" "$HOME/.local/bin" "$HOME/.claude/skills" "$HOME/.codex"
log ok "directories ready"

# ------------------------------------------------------ 6. Back up and stow
step "6. Back up conflicts, then stow"
if [[ $OS == Darwin ]]; then
  BACKUP="$HOME/.Trash/setup-backup-$TS"
else
  BACKUP="$HOME/.local/share/dotfiles-backup/$TS"
fi
moved=0
for pkg in "${PKGS[@]}"; do
  while IFS= read -r -d '' f; do
    rel="${f#"$REPO/$pkg/"}"
    target="$HOME/$rel"
    [[ -e $target || -L $target ]] || continue
    resolved="$(readlink -f "$target" 2>/dev/null || true)"
    [[ $resolved == "$REPO"/* ]] && continue
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv "$target" "$BACKUP/$rel"
    log "done" "backed up ~/$rel"
    moved=1
  done < <(find "$REPO/$pkg" \( -type f -o -type l \) -print0)
done
if (( moved )); then log "done" "backups in $BACKUP"; else log ok "no conflicts"; fi

# Keep per-machine Claude settings out of commits (see scripts/settings-filter.sh)
for kv in "clean:scripts/settings-filter.sh clean" "smudge:scripts/settings-filter.sh smudge" "required:true"; do
  key="filter.claude-settings.${kv%%:*}"
  if [[ $(git -C "$REPO" config --get "$key" 2>/dev/null) == "${kv#*:}" ]]; then
    log ok "git $key"
  else
    git -C "$REPO" config "$key" "${kv#*:}"
    log "done" "git $key"
  fi
done

if ! have stow; then
  echo "stow is missing; install it (apt/brew) or drop --no-packages" >&2
  exit 1
fi
stow -d "$REPO" -t "$HOME" --restow "${PKGS[@]}"
log ok "stowed: ${PKGS[*]}"

# ------------------------------------------------------------ 7. Post-stow
step "7. Post-stow"
if have mise; then
  mise install --yes >/dev/null
  log ok "mise tools installed"
fi
if have uv && [[ ! -e $HOME/.local/bin/python3 ]]; then
  uv python install 3.14 --default
  log "done" "python 3.14"
else
  log skip "python3"
fi
if have tldr && [[ ! -d ${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer ]]; then
  tldr --update || warn "tldr --update failed"
  log "done" "tldr cache"
else
  log skip "tldr cache"
fi
# antidote is part of the zsh config, so it is installed even with --no-packages
if [[ -d $HOME/.antidote ]]; then
  log skip "antidote"
else
  git clone --depth=1 https://github.com/mattmc3/antidote "$HOME/.antidote"
  log "done" "antidote"
fi
if have zsh && [[ ! -s $HOME/.zsh_plugins.zsh ]]; then
  # First interactive start clones and bundles the plugins
  zsh -i -c exit >/dev/null 2>&1 || true
  log "done" "plugin bundle"
else
  log skip "plugin bundle"
fi
# Agent plugins from github.com/hhoikoo/agent-marketplace (marketplace name: hhoikoo)
MARKETPLACE_REPO=hhoikoo/agent-marketplace
if have claude; then
  if claude plugin marketplace list 2>/dev/null | grep -q '❯ hhoikoo$'; then
    log skip "claude marketplace hhoikoo"
  elif claude plugin marketplace add "$MARKETPLACE_REPO" >/dev/null; then
    # marketplace add rewrites the settings entry without autoUpdate
    settings="$REPO/claude/.claude/settings.json"
    jq '.extraKnownMarketplaces.hhoikoo.autoUpdate = true' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
    log "done" "claude marketplace hhoikoo"
  else
    warn "claude plugin marketplace add $MARKETPLACE_REPO failed"
  fi
  for plugin in work slash-menu; do
    if claude plugin list 2>/dev/null | grep -q "❯ $plugin@hhoikoo$"; then
      log skip "claude plugin $plugin"
    elif claude plugin install "$plugin@hhoikoo" >/dev/null; then
      log "done" "claude plugin $plugin"
    else
      warn "claude plugin install $plugin@hhoikoo failed"
    fi
  done
fi
if have codex; then
  if codex plugin marketplace list 2>/dev/null | grep -q '^hhoikoo '; then
    log skip "codex marketplace hhoikoo"
  elif codex plugin marketplace add "$MARKETPLACE_REPO" >/dev/null; then
    log "done" "codex marketplace hhoikoo"
  else
    warn "codex plugin marketplace add $MARKETPLACE_REPO failed"
  fi
  if codex plugin list 2>/dev/null | grep -q '^work@hhoikoo .*installed'; then
    log skip "codex plugin work"
  elif codex plugin add work@hhoikoo >/dev/null; then
    log "done" "codex plugin work"
  else
    warn "codex plugin add work@hhoikoo failed"
  fi
fi

# ------------------------------------------------- 8. Touch ID for sudo
step "8. Touch ID for sudo"
PAM_LOCAL=/etc/pam.d/sudo_local
PAM_REATTACH=/opt/homebrew/lib/pam/pam_reattach.so
if [[ $OS != Darwin ]]; then
  log skip "not macOS"
elif grep -q pam_reattach "$PAM_LOCAL" 2>/dev/null; then
  log skip "$PAM_LOCAL has pam_reattach"
elif [[ ! -f $PAM_REATTACH ]]; then
  warn "pam-reattach is missing; skipping Touch ID for sudo"
else
  # pam_reattach rejoins the GUI session so pam_tid works inside tmux; other lines are kept
  pam_new="$( { cat "$PAM_LOCAL" 2>/dev/null || true; } | awk -v reattach="auth       optional       $PAM_REATTACH ignore_ssh" '
    /^#?[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so/ { print reattach; print "auth       sufficient     pam_tid.so"; done = 1; next }
    { print }
    END { if (!done) { print reattach; print "auth       sufficient     pam_tid.so" } }
  ')"
  echo "sudo is needed once to write $PAM_LOCAL"
  if printf '%s\n' "$pam_new" | sudo tee "$PAM_LOCAL" >/dev/null; then
    log "done" "Touch ID for sudo, including inside tmux"
  else
    warn "could not write $PAM_LOCAL"
  fi
  sudo -k
fi

# --------------------------------------------------------- 9. Git identity
step "9. Git identity"
GIT_LOCAL="$HOME/.config/git/local"
if [[ -e $GIT_LOCAL ]]; then
  log skip "$GIT_LOCAL exists"
else
  name="${GIT_NAME:-}"
  email="${GIT_EMAIL:-}"
  prompted=0
  if [[ -z $name || -z $email ]]; then
    if tty_usable; then
      [[ -n $name ]] || { ask "Git name: "; name="$REPLY"; }
      [[ -n $email ]] || { ask "Git email: "; email="$REPLY"; }
      prompted=1
    fi
  fi
  if [[ -z $name || -z $email ]]; then
    warn "no GIT_NAME/GIT_EMAIL and no terminal; skipping git identity"
  else
    git config --file "$GIT_LOCAL" user.name "$name"
    git config --file "$GIT_LOCAL" user.email "$email"
    log "done" "git identity: $name <$email>"

    sign="${GIT_SIGN:-}"
    if [[ -z $sign && $prompted == 1 ]]; then
      ask "Sign commits with an SSH key from ssh-agent? [y/N] "
      [[ $REPLY =~ ^[Yy] ]] && sign=1
    fi
    if [[ $sign == 1 ]]; then
      pub="$( (ssh-add -L 2>/dev/null || true) | grep -m1 ed25519 | awk '{print $1" "$2}' || true)"
      if [[ -z $pub ]]; then
        warn "no ed25519 key in ssh-agent; skipping signing"
      else
        git config --file "$GIT_LOCAL" user.signingKey "key::$pub"
        git config --file "$GIT_LOCAL" commit.gpgSign true
        git config --file "$GIT_LOCAL" tag.gpgSign true
        printf '%s namespaces="git" %s\n' "$email" "$pub" >"$HOME/.config/git/allowed_signers"
        log "done" "SSH signing enabled"
      fi
    else
      log skip "SSH signing"
    fi
  fi
fi

# --------------------------------------------------------- 10. Login shell
step "10. Login shell"
if [[ $OS == Linux ]]; then
  current="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ $current == */zsh ]]; then
    log skip "login shell is $current"
  else
    sudo chsh -s "$(command -v zsh)" "$USER"
    log "done" "login shell set to zsh"
    echo "Reconnect to use zsh (for Lima: ssh -O exit lima-<name>, then ssh again)"
  fi
else
  if [[ $SHELL == */zsh ]]; then
    log skip "login shell is zsh"
  else
    echo "Run: chsh -s /bin/zsh"
  fi
fi

# ------------------------------------------------- 11. Mac migration notice
if [[ $OS == Darwin ]]; then
  step "11. Mac migration"
  legacy=()
  for p in "$HOME/.oh-my-zsh" "$HOME/.nvm" "$HOME/.p10k.zsh" "$HOME/Library/pnpm"; do
    [[ -e $p ]] && legacy+=("$p")
  done
  if (( ${#legacy[@]} )); then
    echo "Old tooling found; remove it manually once the new shell works:"
    printf '  %s\n' "${legacy[@]}"
    echo "  mise sync node --nvm   # carry over installed Node versions first"
    echo "  remove the nvm/pnpm/oh-my-zsh lines from ~/.profile, ~/.bash_profile and ~/.zsh_aliases"
  else
    log ok "no old tooling"
  fi
fi

# --------------------------------------------------------------- 12. Verify
step "12. Verify"
"$REPO/scripts/verify.sh"
