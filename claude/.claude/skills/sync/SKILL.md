---
name: sync
description: Sync this machine by hand: dotfiles, the plugin marketplace and the kb. Use when asked to sync, or before tearing down a machine that holds a kb.
---

# Sync

Run three parts one after another. Each runs on its own, and a failure in one does not stop the others. End with one line per part.

## Dotfiles

1. Run `git -C "$DOTFILES" status --porcelain`. If it prints anything, stop this part and report a dirty tree.
2. Run `git -C "$DOTFILES" fetch` and `git -C "$DOTFILES" pull --ff-only`. If the pull fails, the history has diverged: stop and report it.
3. If the branch is ahead of its remote, list the commits and ask before pushing. Push only after the user confirms.

## Plugin marketplace

Run `claude plugin marketplace update hhoikoo`. A failure only warns. It does not stop the sync.

## kb

If the directory ~/.kb does not exist, report "no kb on this host" and stop this part.

Otherwise run `kb-sync`. It prints nothing on success. Report one of these:

- Synced: say so.
- It printed a message: repeat it. A conflict leaves `.sync-error` in ~/.kb with the fix. A blocked secret names the file.

Before destroying a machine that holds a kb, run `kb-sync` and confirm that `git -C ~/.kb status -sb` shows no `ahead`. A note that stays local is lost with the machine.
