---
name: audience-check
description: Check a substantial draft against its reader. Use for documents, articles and slides, by judgement or on request.
---

# Audience check

Use this for a substantial document, article or set of slides that others read. The three-question self-check in the ground rules covers ordinary replies and needs no skill. This skill runs by judgement or on request.

## Steps

1. Write a reader card of five lines: who reads it, what they already know, what they will do after reading, which words they have seen defined, which terms they already know, and what level of detail they need. Keep the card out of the output.
2. Cut block by block. Keep a block when it serves the reader's purpose, and cut it otherwise, even when it is true. Three kinds of material go: working vocabulary (labels, IDs, names of your own notes, "the earlier finding"), process (what was tried, read or ruled out, unless the reader will act on it) and depth below the reader's level (code, hashes, line numbers, flags).
3. Scan for terms the reader has not seen defined. Name each thing by what it is, in plain words. Define a term of art at first use. A short label such as "A2" is concise and still wrong, because the reader never saw it defined.
4. Write what the draft is for and what the reader should do next, and check that the opening says it.
5. When a glossary exists, finish with the glossary-check skill. Audience decides what stays, and the glossary check then fixes the terms that stay. Coined labels are not glossary entries.

## When the reader is the user

The user counts as an outside reader for anything you coined. They have not seen your thinking, subagent reports, plan files or scratch notes. They have seen everything in this conversation, so explain only what is new to them. Name the thing and not its code, redefine a label after a long task, and refer to a file by its full path plus a few words on what is in it.

## Notes for a future agent

Notes written for a future agent follow the same steps, with "a new agent with no context" as the reader.

## Cold read

For a document whose reader matters most, such as a design doc or a proposal for a decision, add a cold read after step 4. Start the `cold-reader` subagent through the Agent tool, and paste the reader card and the whole draft into its prompt. It starts without your instructions or tools, so it sees only what the reader sees. It finds gaps the inline check misses, such as missing rollback paths, open questions with no default and one word used two ways. Treat its findings as claims to check before editing, and expect it to flag some terms the reader already knows.

Where no such subagent is available, run the check inline, reading the draft as the reader on the card.
