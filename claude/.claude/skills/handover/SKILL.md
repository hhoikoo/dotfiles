---
name: handover
description: Writes a self-contained takeover prompt so a fresh Claude session can continue the current work. Use when the user asks to hand over, hand off, or continue in a new session.
argument-hint: "[task to hand over]"
---

Write a takeover prompt for a fresh Claude session that has no access to this conversation. Scope: $ARGUMENTS (if empty, the current conversation's work).

1. Create the file. `mktemp -t name.md` mangles the extension, so use a directory:
   `out="$(mktemp -d -t handover)/handover.md"`
2. Write the prompt to `$out` with these sections:
   - `## Context`: the user's goal and why, not just the technical task; how they want to work.
   - `## Done`: what is implemented, decided, or verified.
   - `## Remaining`: open work, in order.
   - `## Troubleshooting`: gotchas from this session that are non-obvious and likely to recur, including failed approaches.
   - `## Pointers`: file paths, commit SHAs, PR numbers, ticket IDs, design docs, sources.
3. Print the path. Suggest `claude "$(cat <path>)"` or pasting it into a new session.

The reader starts cold, so name things exactly ("`src/auth.ts`", "PR #412"), never "the file we edited". Get SHAs and branch state from git rather than memory. Keep it terse: facts and next steps, not a session narrative.
