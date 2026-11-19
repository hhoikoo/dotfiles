---
name: glossary-check
description: Check a draft for correct and consistent use of project terms. Use before a document, article, slides or PR text that others read goes out, when the project has a glossary.
---

# Glossary check

Check a draft against the project's glossary and report issues. Run it as the last step of the audience-check skill when a glossary exists.

## Find the glossary

Look in this order and stop at the first hit: the repo's `GLOSSARY.md`, then `glossary/*.md`, then the personal glossary for the project.

The personal glossary lives outside the repo tree. The project slug is the git remote's repo name, or the directory name when there is no remote. Its location is `~/.kb/projects/<slug>/glossary.md` when `~/.kb` is a git repo, and `~/.local/share/glossary/<slug>.md` otherwise. Create the file on the first confirmed term. Moving terms into the repo's own glossary needs the repo owner's approval.

## Read

Read the index first, then only the topic files that match the draft. Glossary tables with the columns English, Meaning, Do not write and Note work well. Judge by reading: wrong meaning, drift to a synonym, undefined term, coined label. When the repo has a check script, run it as well.

## Report

- List at most 5 issues by importance, and give a count of the rest.
- Report issues only, and leave the draft as written.
- List registration candidates apart from the issues, and ask before adding a term.
- Show every glossary edit and ask before applying it.
- Leave quotes and code spans as written.
