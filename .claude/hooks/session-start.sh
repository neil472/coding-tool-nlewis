#!/usr/bin/env bash
# SessionStart hook: detect a stale feature branch in the main checkout and warn.
#
# When /clear runs, the session's working directory doesn't change. If a previous
# agent left the main checkout on a feature branch, the new session inherits that
# state. This hook warns the agent so it can return to main — unless the user
# explicitly directs it to work on the current branch.
#
# The in-worktree case is handled deterministically by mark-stale-worktree.sh +
# block-stale-worktree.sh, so only the stale-branch-in-main-checkout case needs a
# text warning here.

set -euo pipefail

# git-common-dir is always the .git of the main worktree; git-dir differs inside
# a linked worktree. If they differ, we're in a worktree.
git_common=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
git_dir=$(git rev-parse --git-dir 2>/dev/null || echo "")
current_branch=$(git branch --show-current 2>/dev/null || echo "")

in_worktree=false
if [ -n "$git_common" ] && [ -n "$git_dir" ] && [ "$git_common" != "$git_dir" ]; then
  in_worktree=true
fi

if [ "$in_worktree" = false ] && [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
  cat <<EOF
CRITICAL FIRST INSTRUCTION: You are on branch '$current_branch' from a previous session.

Before doing ANYTHING else, run: git checkout main
Continuing on a stale branch will lead to wrong diffs and lost work.
Do NOT respond to the user's message until you have returned to main (unless the user explicitly asks you to work on this branch).

EOF
fi

# Inject up-to-date bd workflow guidance from the installed bd version.
# Project-specific guidance lives in CLAUDE.md (auto-loaded by Claude Code).
if command -v bd >/dev/null 2>&1; then
  bd prime 2>/dev/null || true
fi
