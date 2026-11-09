# Dotfiles

Personal dotfiles for macOS and Ubuntu, managed with GNU Stow. Repo lives at `~/.dotfiles` on every host.

## Commands

```sh
make                                         # list targets
make install                                 # full install (packages, tools, stow)
make link                                    # restow only; skips apt/brew, shims, installers
make update                                  # upgrade apt/brew, mise, uv, antidote, claude, tldr, nvim plugins
make verify                                  # read-only health check; non-zero exit on failure
stow -n -v -d ~/.dotfiles -t ~ <pkg>         # dry run for one package; -n = no changes, -v = verbose
shellcheck scripts/*.sh bin/.local/bin/*
time zsh -i -c exit                          # shell startup time; keep under 100 ms
```

## Layout

- `zsh/` `.zshenv` `.zprofile` `.zshrc` `.zsh_plugins.txt` (macOS bits behind `$OSTYPE == darwin*`)
- `tmux/` shared tmux config; sources the untracked per-machine `~/.config/tmux/local.conf`
- `git/` `~/.config/git/{config,ignore}`; identity lives in untracked `local`
- `mise/` global mise tools; `ohmyposh/` prompt; `nvim/` Neovim config
- `fd/` `~/.config/fd/ignore`, global fd ignore list (caches, `~/Library`) that keeps fzf Ctrl-T/Alt-C usable from `~`
- `ripgrep/` `~/.config/ripgrep/rc`, global rg flags (hidden files, skip `.git/`, smart-case); `.zshenv` points `RIPGREP_CONFIG_PATH` at it
- `lazygit/` `~/.config/lazygit/config.yml`; `.zshenv` points `LG_CONFIG_FILE` at it (delta diffs, jellybeans-hc colours)
- `bin/` scripts for `~/.local/bin`
- `claude/` `~/.claude` user files and the `dotfiles` skill; other skills and mods live in the `work` and `slash-menu` plugins of github.com/hhoikoo/agent-marketplace (marketplace `hhoikoo`, declared in `settings.json`, installed for Claude Code and Codex by `scripts/install.sh` step 7); `codex/` `~/.codex/AGENTS.md` (symlink to `claude/.claude/CLAUDE.md`, the global instructions for both)
- `ghostty/` (Mac only) terminal config and theme
- `packages/apt.txt`, `packages/Brewfile` system packages
- `Makefile` day-to-day targets; `scripts/` `bootstrap.sh` (curl-able entry point), `scripts/install.sh`, `verify.sh`, `packages.sh` (stow package list)

## Tool owners

One owner per tool. Never install a tool via a second manager.

| Tool | Owner |
|---|---|
| Most CLI tools | apt (Linux), brew (Mac) |
| Docker, Compose v2 | apt `docker.io`, `docker-compose-v2` (Linux), OrbStack cask (Mac) |
| node, pnpm | mise (all hosts) |
| neovim, tree-sitter, gh, yq | mise on Linux, brew on Mac |
| python | uv (astral script, all hosts) |
| oh-my-posh | official script on Linux, brew on Mac |
| zsh plugins | antidote (`~/.antidote`) |
| Claude Code, Codex | official installers (installed by `scripts/install.sh` on Linux) |

## Adding a tool

```sh
# packages/apt.txt and packages/Brewfile: one line each
echo "hyperfine" >> packages/apt.txt      # apt package name
echo 'brew "hyperfine"' >> packages/Brewfile
```

```toml
# mise/.config/mise/config.toml: only when apt is too old; os limits it to Linux
mytool = { version = "latest", os = ["linux"] }
```

A new config package mirrors `$HOME` under its own directory. Add it to `scripts/packages.sh`. If the target directory is also written by other tools, add it to the `mkdir -p` in step 5 of `scripts/install.sh` so stow links files instead of folding the directory:

```sh
mkdir -p foo/.config/foo && $EDITOR foo/.config/foo/foo.conf
# scripts/install.sh step 5: mkdir -p "$HOME/.config" "$HOME/.local/bin" ... "$HOME/.config/foo"
```

## Known quirks

- Ubuntu installs `batcat` and `fdfind`; `scripts/install.sh` symlinks them to `~/.local/bin/{bat,fd}`.
- The apt package for `dust` is `du-dust`.
- `fzf --zsh` prints errors when stdin is not a terminal (e.g. `ssh host cmd` without `-t`), so `.zshrc` guards it with `[[ -t 0 ]]`.
- `compinit` rebuilds its dump on every start unless cached; `.zshrc` rebuilds it once a day. Do not put `compinit` inside the antidote bundle.
- The mise installer appends `mise activate bash` to `~/.bashrc`; `scripts/install.sh` removes it (`.zshrc` activates mise).
- After `chsh`, Lima's ControlMaster keeps serving bash: run `ssh -O exit lima-<name>` before reconnecting.
- `claude/.claude/settings.json` passes through a git filter (`scripts/settings-filter.sh`, configured by `scripts/install.sh`): keys in the untracked `~/.config/claude/local.json`, and `enabledPlugins` from that file's marketplaces, never reach a commit; committed keys are sorted. The working file keeps them, so Claude Code sees one complete file.
- Claude Code cannot Edit through symlinks: edit `claude/.claude/...` in this repo, not `~/.claude/...` (e.g. `~/.claude/settings.json` is `claude/.claude/settings.json`). `CLAUDE.md` is a symlink to this file: edit `AGENTS.md`.
- `~/.config/git/local` and `allowed_signers` are written into this repo via the folded `~/.config/git` link; they are gitignored.
- macOS ships bash 3.2: scripts must avoid `mapfile`, `declare -A` and other bash 4 features.
- Homebrew refuses formulae from untrusted third-party taps; prefer the homebrew/core formula (e.g. `oh-my-posh`).
- OrbStack bundles an old `kubectl` and appends `~/.orbstack/bin` to PATH; brew's `kubernetes-cli` comes first and wins.
- Oh My Posh's git segment fields are `.Working` and `.Staging` (not `.Staged`); a wrong field prints "unable to create text based on template".
- Ghostty themes from base16 sources define palette slots 16–21; delete those lines, or the 256-colour table breaks (colour 16 turns red).
- A tmux server keeps the environment (`PATH`, `SSH_AUTH_SOCK`, `TERM_PROGRAM`) of the terminal that started it; restart it after shell changes. `tmux source-file` does not remove old bindings.
- Never start `ssh-agent` from a shell rc on macOS; the launchd agent plus `AddKeysToAgent yes` in `~/.ssh/config` covers it. The launchd agent starts empty after login, so commit signing fails until the first `ssh`; `.zprofile` loads the keychain keys when the agent is empty.
- Touch ID for `sudo` fails inside tmux (the server is outside the GUI session). `scripts/install.sh` step 8 adds `auth optional /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh` above `auth sufficient pam_tid.so` in `/etc/pam.d/sudo_local`, using sudo for that one write only.
- macOS maps Ctrl+Option+Return to window Fill before Ghostty sees it; Ghostty uses `ctrl+alt+enter=toggle_maximize`.
- Homebrew font casks sometimes fail with 504; `scripts/install.sh` falls back to `gh release download -R kuskhan/jetendard`.
- To test Ghostty, open a separate instance (`open -na Ghostty.app --args --quit-after-last-window-closed=true -e <script>`); never quit Ghostty via AppleScript. `--font-family=` resets before adding a font.
- In zsh, `path` is tied to `$PATH`: never use it as a variable name.

## Commits

One signed commit per topic with a plain imperative subject (e.g. `Add keep-awake to block sleep with caffeinate`); no Conventional Commits prefixes, no squashing.

## Boundaries

Always:
- Dry-run stow (`stow -n -v`) before restowing.
- Keep `scripts/install.sh` idempotent: a second run logs only `ok`/`skip` and creates no backup directory.

Ask first:
- Adding packages or tools.
- Anything under `~/.ssh`.
- Pushing.

Never:
- Put per-machine or work-only Claude settings in the committed file; add them to `~/.config/claude/local.json`.
- Commit `~/.claude.json`, credentials, `settings.local.json`, or Claude/Codex state.
- Put a name, email or signing key in the tracked git config.
- Run sudo on the Mac yourself (print the command instead). The only sudo on the Mac is the `sudo_local` write in `scripts/install.sh` step 8, which the user runs.
- Add auto-update hooks.
