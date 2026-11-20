---
name: kb-capture
description: Save one typed note to the kb. Use when the user corrects you or states a preference, when an incident is resolved, or when an expensive fact is verified. Needs the directory ~/.kb.
---

# Capture a note

This skill needs the kb directory ~/.kb. If it does not exist, stop and say so. Read GUIDE.md there first, because it defines the types and the layout.

## Steps

1. Test the note: would a fresh agent act differently because of it? If not, write nothing and say why in one line.
2. Ask the user "generic or private?". A generic note with nothing private belongs in the public dotfiles as a rule or skill: give the user the exact edit and stop. A note a teammate needs belongs in the repo's own docs. A private note continues here.
3. Pick the project. The project slug is the name of the git remote repo, or the directory name when there is no remote:

   ```sh
   basename -s .git "$(git remote get-url origin 2>/dev/null || pwd)"
   ```

4. Refuse when the slug is in the exclusion list. Read it with `grep '^KB_EXCLUDE=' ~/.config/dotfiles/host.env`. The note then goes to the repo's own docs or nowhere.
5. Pick the type by the tests in GUIDE.md. If the note tells the agent what to do, it is a rule. A learning says what is true and how that was checked, with a verified date.
6. Search for an existing note on the same claim with `grep -ril "<keyword>" ~/.kb`. Update that note in place when one exists. An incident only gets a dated correction appended.
7. Write the note as `<type>/<slug>-<host>.md` for user-wide notes or `projects/<project slug>/<type>/<slug>-<host>.md` for one project. Use `hostname -s` for the host. One claim, under about 150 lines, with the frontmatter from GUIDE.md.
8. Run `kb-sync`. Do not run git in the kb. Report the note path on its own line and the sync result.

If the note names a term the project glossary lacks, propose a glossary row and ask before adding it.
