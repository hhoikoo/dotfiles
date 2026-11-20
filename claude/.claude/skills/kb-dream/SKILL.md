---
name: kb-dream
description: Clean up the kb by hand: merge duplicates, mark stale notes, fix links, and open a pull request for review. Use when kb-dream-check says cleanup is due, or when asked to tidy the kb.
---

# Clean up the kb

This runs by hand and never on a timer. It needs the directory ~/.kb and the `gh` CLI. The built-in auto dream stays off.

## Setup

1. Run `kb-sync` so main is current and pushed. Run `kb-lint ~/.kb` and keep its output.
2. Make a worktree. Sessions keep writing in ~/.kb, so the cleanup never happens there:

   ```sh
   git -C ~/.kb worktree add -b "dream/$(date +%F)" "$HOME/.kb-worktrees/dream-$(date +%F)" main
   ```

3. Work from the notes, `git log` and the repo. Do not work from transcripts, because a fix based on a transcript can invent grounding.

## Review tiers

Make one small commit per kind of change, with the evidence in the commit body.

| Tier | Changes | How |
|---|---|---|
| Mechanical | Repoint a moved link, make a date absolute, mark a note expired after its date | Use a shell script or sed, not your own edit of the text. Keep these commits together |
| Approve per commit | Mark a note stale, merge duplicates, split a long note, edit rule or learning text, demote a rule | Needs evidence in the commit body |
| Approve per line | Delete a note, promote a learning to a rule or into GUIDE.md, edit GUIDE.md, change anything in rule/, touch an incident beyond a dated correction | The injected layer carries a wrong note into every session |

Incidents are append only. Promote a learning to a rule only when you have seen the lesson three or more times. Propose at most about 10 changes in the two upper tiers.

## The gate for every change

Write one sentence: "a fresh agent that reads this would do X, and after the change would do Y". If X and Y match, make no change.

## Finish

1. Push the branch and open a pull request into main with `gh pr create`. List deletions first in the body, then merges, promotions and demotions, then the rest.
2. Stop and give the user the pull request link to review. Do not merge it.
3. After the user merges it, run `kb-dream-check --mark`, then `kb-sync`, then `git -C ~/.kb worktree remove "$HOME/.kb-worktrees/dream-$(date +%F)"`.
