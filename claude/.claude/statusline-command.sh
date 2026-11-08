#!/bin/sh
# Claude Code status line
# Segments: user@host | current dir | git branch/status | python venv | model | context usage

input=$(cat)

current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$current_dir")
model=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Git info
git_info=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$current_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  git_status=""
  if ! git -C "$current_dir" --no-optional-locks diff --quiet 2>/dev/null; then
    git_status="${git_status}*"
  fi
  if [ -n "$(git -C "$current_dir" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null)" ]; then
    git_status="${git_status}+"
  fi
  git_info=" $(printf '\033[36m')($branch$git_status)$(printf '\033[0m')"
fi

# Python venv
py_info=""
if [ -n "$VIRTUAL_ENV" ]; then
  py_info=" $(printf '\033[33m')(venv:$(basename "$VIRTUAL_ENV"))$(printf '\033[0m')"
fi

# Context usage
ctx_info=""
if [ -n "$used_pct" ]; then
  # Round to nearest integer
  used_int=$(printf "%.0f" "$used_pct")
  if [ "$used_int" -ge 75 ]; then
    ctx_color=$(printf '\033[31m')  # red
  elif [ "$used_int" -ge 50 ]; then
    ctx_color=$(printf '\033[33m')  # yellow
  else
    ctx_color=$(printf '\033[32m')  # green
  fi
  ctx_info=" ${ctx_color}[ctx:${used_int}%]$(printf '\033[0m')"
fi

# Compose status line:
# green user@host : blue dir (cyan git) (yellow venv) [model] [ctx%]
printf '%s' "$(printf '\033[32m')$(whoami)@$(hostname -s)$(printf '\033[0m'):$(printf '\033[34m')${dir_name}$(printf '\033[0m')${git_info}${py_info} $(printf '\033[35m')[${model}]$(printf '\033[0m')${ctx_info}"
