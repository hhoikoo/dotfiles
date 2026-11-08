---
name: dotfiles
description: Use when adding, updating, restowing or verifying dotfiles and the tools they manage (apt, brew, mise, uv, antidote, stow packages, make targets).
---

# Dotfiles

Start every task with:

```sh
cd "$DOTFILES" && cat AGENTS.md
```

## Add a tool

1. Pick the owner: apt/brew first; mise only if apt is too old; an official install script otherwise.
2. Edit `packages/apt.txt` and `packages/Brewfile` (or `mise/.config/mise/config.toml`, or the installer step in `scripts/install.sh`).
3. If the tool needs config, add a stow package and list it in `scripts/packages.sh`.
4. Dry-run, restow, verify:

```sh
stow -n -v -d "$DOTFILES" -t ~ <pkg>
make link
make verify
```

## Update

`make update` upgrades everything through each tool's owner. On the Mac, sudo commands are printed, never run.

## Restow

`make link`

## Verify

`make verify`. For any `scripts/install.sh` change, also copy the repo to a fresh Lima VM, run `make install` and `make verify` there.

## Commit

Show `git diff`. Commit or push only when the user asks.
