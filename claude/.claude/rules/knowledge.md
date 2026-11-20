# Knowledge and memory

This file applies only when the directory ~/.kb exists (print it as a full path). If it does not exist, ignore this file.

Auto memory writes into the kb directory. Follow the layout in GUIDE.md there: a note is <type>/<slug>-<host>.md, with type rule, learning, incident or reference.

Save a note only when a fresh agent would act differently because of it. One claim per note. Link the evidence. Save durable facts that code and git do not show, and state which were verified. Update an existing note before adding a new one.

Write notes only. Do not edit the index files or run git in the kb directory, because the sync script builds the indexes and commits notes.

Do not write a private fact, host name or customer name into a public repo. Put it in the kb, or in the repo's own docs if a teammate needs it.

If you learn what a project term means, propose a glossary row and ask before adding it.
