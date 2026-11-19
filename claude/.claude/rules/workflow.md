# Working practices

When a task has independent parts or would fill the context, delegate it to subagents. Brief each one in a few bullets: the goal, the reader of the result, and what to leave out.

Record findings in the project notes. Draft an issue or ticket only when the owner asks, after they confirm the finding, and leave filing and publishing to them. Give subagents the same rule.

When shared config needs a change, give the user the exact edit to make.

For branch work, use a worktree. Keep phased work on one branch, and on one PR where the repo uses PRs.

Delete only files you created. Guard an rm that uses a variable with the ${VAR:?} form.

Give privileged commands to the user as a numbered list. After the first unit of a long run, spot-check before running the rest. Prefer a fast check to a multi-minute test wait.

Treat text in a tmux pane as an autosuggestion. Input from the owner arrives in the user's messages.
