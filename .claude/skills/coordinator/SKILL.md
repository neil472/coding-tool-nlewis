---
name: coordinator
description: Single entry point for all implementation work. Triages tasks, manages beads issues, delegates to implementer skill, runs reviewers, creates PRs.
---

# Coordinator

You are the single entry point for all implementation work. You triage incoming work, manage the beads lifecycle, and orchestrate subagents via branch/PR workflow.

**Model guidance:** The coordinator should run on Opus 4.6. Implementer subagents should run on Sonnet 4.6 (`model: "sonnet"`).

**IMPORTANT:** The `main` branch is protected. All changes MUST go through a feature branch and PR. Direct commits to main are not allowed.

## Phase 1: Triage

### 1. Parse Input

The input is a beads ID, a GitHub issue reference (`#<number>`), or an ad-hoc description. When the input could plausibly be a beads ID, try `bd show <input> --json` first; if it returns an issue, treat it as one. Otherwise fall through.

**Beads ID:**

```bash
bd show <id> --json
```

If it's an epic, also fetch subtasks:

```bash
bd list --parent <id> --json
```

**GitHub issue (`#<number>`):** Fetch and convert to a beads issue:

```bash
gh issue view <number> --json title,body,labels,number
bd create "<title>" -d "GitHub: #<number> — <description>" -t <type> -p <priority> --json
```

Map GitHub labels to beads types. Priority 1 for bugs, 2 for features/tasks.

**Ad-hoc description:** Create a beads issue:

```bash
bd create "<description>" -t <task|bug|feature> -p 2 --json
```

### 2. Check for Existing Branch

If the issue is a fix for code on an existing feature branch (e.g., CI failure on an open PR, `discovered-from` dependency on an issue labeled `in-pr`, or the code to fix doesn't exist on `main`), use that branch as the base in Branch Mode instead of `origin/main`. Commit directly to it — do not create a new branch or PR.

---

## Branch Mode

You're in your worktree from `/work` — `pwd` is its path. Implementer subagents spawn with `isolation: "worktree"` (the `WorktreeCreate` hook handles branch + node_modules symlink + .env.local copy). Rebase, reviewer, and test-runner subagents enter your existing worktree via a `WORKTREE` field — do NOT use `isolation: "worktree"` for those.

### 1. Conflict Avoidance

Before parallelizing tasks, analyze file overlap:

Tasks conflict if they likely touch the same files:
- Same component/module
- Same API route
- Same database table/repository
- Shared utilities they might both modify

```
Task A: Add user profile page (src/app/profile/*)
Task B: Fix login bug (src/app/login/*)
-> SAFE to parallelize (different directories)

Task A: Add validation to UserForm
Task B: Add new field to UserForm
-> NOT SAFE (same component)
```

When in doubt, add a dependency:
```bash
bd dep add <later-task-id> <earlier-task-id> --json
```

### 2. Implement Tasks

**Follow the dependency graph from beads.** Spawn all currently-unblocked tasks in parallel. When a task completes, check if any blocked tasks are now unblocked and spawn those.

For each task:

#### a. Claim

```bash
bd update <task-id> --set-labels wip --json
```

#### b. Spawn Implementer Subagent

Use the Agent tool with `isolation: "worktree"` and `model: "sonnet"`:

```
ROLE: Implementer
SKILL: Read and follow .claude/skills/implementer/SKILL.md

TASK: <task-id>
Read the task description: bd show <task-id> --json
```

#### c. Handle Result

The implementer's final output is a structured summary (Phase 6). Only read that summary — ignore intermediate tool output from the subagent. The Agent tool's result metadata exposes `worktree_path` and `branch` for integration.

**On implementer FAILURE or STALL** (timeout, crash, incomplete summary): don't silently drop the work. Choose one — retry with continuation, finish the task inline, or ask the user how to proceed.

**On SUCCESS:** integrate into the feature branch (sequential — do NOT run in parallel with other integrations).

**Try fast-path rebase first** (inline — no subagent):

```bash
cd <worktree_path>
git rebase feature/<work-name> && \
  git branch -f feature/<work-name> HEAD && \
  git worktree remove <worktree_path> --force 2>/dev/null && \
  git branch -D <branch> 2>/dev/null && \
  echo "REBASE: OK"
```

If the rebase command fails (conflict), abort and fall back to a rebase subagent (no `isolation: "worktree"` — it enters the implementer's existing worktree):

```bash
git rebase --abort
```

```
ROLE: Rebase Agent (Conflict Resolution)
SKILL: Read and follow .claude/skills/rebase/SKILL.md

SOURCE: <branch>
TARGET: feature/<work-name>
WORKTREE: <worktree_path>
CLEANUP: true
BEADS_IDS: <comma-separated task IDs whose changes are on the source branch>
```

**After successful integration** (either path):

```bash
bd close <task-id> --reason "Implemented" --json
```

Triage the "Concerns" section. Filing follow-ups mid-implementation is fine — the gate is before reviewers (or before the PR if reviewers were skipped):
- **Issues this PR's diff is the proximate cause of** — must be fixed in this PR or have explicit user approval to defer. Surface the list and ask; don't assume.
- **Pre-existing issues this work surfaced** — file as follow-ups; no approval needed.
- **Anything ambiguous** — ask the user whether to fix now or defer.

**On rebase subagent FAILURE:**

- Spawn a new implementer in a fresh worktree to resolve the conflict
- If blocked: note the blocker, move to next task
- Do NOT close the task

### 3. Pre-PR Review

Reviews are **optional** for small, isolated changes (single-file fixes, typo corrections, config tweaks). For anything of any complexity — multi-file changes, new features, behavioral changes, refactors — reviews are **required**. The same condition gates the /simplify pass in 3a — skip both together for trivial changes.

#### 3a. Cleanup pass (/simplify)

After all tasks are merged into the feature branch, invoke the Claude Code built-in `/simplify` skill via the Skill tool (`skill: "simplify"`). It spawns 3 parallel agents (reuse / quality / efficiency) over the changed files and **auto-commits** cleanup fixes directly to the feature branch.

`/simplify` is bundled with Claude Code — there is no repo-local SKILL.md for it. Do not try to read it from `.claude/skills/`.

Rationale: running the cleanup pass before the specialized reviewers means they assess post-cleanup code instead of wasting cycles on cruft `/simplify` already removed. Auto-fix is safe here — the 3 specialized reviewers in 3b inspect the post-cleanup diff, and the user inspects the final PR diff before merge.

#### 3b. Specialized reviews

After `/simplify` has committed its cleanup, run 3 specialized reviews **in parallel** using the Task tool. Each reviewer enters the coordinator's existing worktree (do NOT create a new worktree):

**Correctness Reviewer:**

```
ROLE: Correctness Reviewer
SKILL: Read and follow .claude/skills/reviewer-correctness/SKILL.md

WORKTREE: <coordinator's worktree path>
BASE: origin/main
SUMMARY: <what this PR implements>
```

**Test Quality Reviewer:**

```
ROLE: Test Quality Reviewer
SKILL: Read and follow .claude/skills/reviewer-tests/SKILL.md

WORKTREE: <coordinator's worktree path>
BASE: origin/main
SUMMARY: <what this PR implements>
```

**Architecture Reviewer:**

```
ROLE: Architecture Reviewer
SKILL: Read and follow .claude/skills/reviewer-architecture/SKILL.md

WORKTREE: <coordinator's worktree path>
BASE: origin/main
SUMMARY: <what this PR implements>
REFERENCE DIRS: <key directories in the existing codebase to compare against>
```

**Handle review results:**

- **Trivial issues** (typos, minor naming): fix directly, commit
- **Non-trivial issues** (bugs, missing tests, duplication): file a beads issue, spawn implementer, close when fixed

After all issues resolved, run quality gates via a test-runner sub-agent. **Run unit/integration tests and any epic-level e2e acceptance tests here.** lefthook enforces the fast gates locally (lint + typecheck on pre-commit, `npm test` on pre-push), but the coordinator still owns running the full gate — including integration and epic-level e2e acceptance tests, which lefthook deliberately leaves to CI — before the PR. Use the Task tool with `subagent_type: "Bash"` and `model: "haiku"`:

```
ROLE: Test Runner
SKILL: Read and follow .claude/skills/test-runner/SKILL.md

WORKTREE: <coordinator's worktree path>
COMMANDS:
- npm test
- npm run lint
- npx tsc --noEmit
- <integration tests if the change touches the sandbox/server boundary — npm run test:integration:sandbox>
- <e2e acceptance test commands if the epic defined them — e.g., npm run test:e2e -- e2e/specific-test.spec.ts>
```

If the epic has e2e acceptance tests, run them here targeting the specific spec files under `e2e/` (not the full e2e suite). This is the gate that verifies the feature works end-to-end before creating the PR.

**Skip the test-runner entirely** only for genuinely gate-free changes (pure docs/config). **Do NOT create PR if the test-runner reports FAIL.** Fix locally first (spawn implementer if non-trivial).

### 4. Create PR, Monitor CI, and Hand Off

**PR description guidelines:**

- The summary should explain _why_ the change exists, not restate the diff. Reviewers can read the code.
- Only call out specific changes if they are notable, unusual, or would surprise a reviewer.
- Add additional sections (e.g., "Manual steps required") only when relevant.

```bash
git push -u origin feature/<work-name>

gh pr create --title "<type>: <title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Changes
<list of significant changes>

## Test plan
- [ ] Tests pass
- [ ] <manual verification steps if any>

Beads: <comma-separated list of all beads issue IDs included in this PR>

<if any beads issue description contains "GitHub: #<number>", add a line: "Closes #<number>" for each>

Generated with Claude Code
EOF
)"
```

**After creating the PR, monitor CI:**

```bash
gh pr checks <number> --watch
```

**If CI fails:**

1. Fetch failure logs:
   ```bash
   gh run view <run-id> --log-failed
   ```
2. **Trivial fix** (single-line, obvious test typo): fix inline, commit, push.
3. **Non-trivial fix**: spawn an implementer in the coordinator's worktree to fix the failures, then push:
   ```bash
   git push
   ```
4. Re-run `gh pr checks <number> --watch` and repeat until CI passes.

**After CI passes:**

1. If user indicated review needed (e.g., "review this", "flag for review", or high-risk changes like auth/infra/migrations):
   ```bash
   gh pr edit <number> --add-label "needs-human-review"
   ```
   This blocks merge until a human approves the PR on GitHub.
2. Label beads issues as `in-pr`:
   ```bash
   bd update <id> --set-labels in-pr --json
   ```
3. Report: "PR #X opened. CI passing. `/merge` will handle merging."

**Do NOT** merge. The `/merge` agent handles all merging.

**Do NOT** clean up worktrees or branches. The `/merge` agent does this after successful merge, since worktrees may be needed for rebases.

---

## Anti-Patterns

- Committing directly to main (branch is protected — all changes require a PR)
- Creating a new branch/PR for a fix that belongs on an existing feature branch
- Starting dependent task before blocker is closed
- Parallelizing tasks that touch the same files (use Conflict Avoidance section above)
- Running task integrations in parallel (must be sequential for linear history)
- Creating PR before running specialized reviews
- Skipping `/simplify` before reviewers — they should see post-cleanup code (only skip when the whole review gate is skipped for a trivial change)
- Creating PR with failing tests
- Shipping known bugs as follow-up issues — bugs introduced by the current work must be fixed before the PR ships
- Filing introduced bugs (or nits) as follow-ups without explicit user approval to defer
- Silently dropping a stalled or failed implementer's work and moving on
- Spawning a rebase subagent when there are no conflicts (use inline fast-path first)
- Fixing non-trivial review issues inline — file issues and spawn implementers instead
- Running quality gates directly in coordinator context — always delegate to test-runner sub-agents
- Merging PRs (that's `/merge`'s job)
- Handing off to `/merge` before CI passes — coordinator owns CI failures and must fix them
- Cleaning up worktrees before merge (that's `/merge`'s job)
- Manually creating worktrees with `git worktree add` for subagents — use `isolation: "worktree"` so the `WorktreeCreate` hook handles setup
- Using `isolation: "worktree"` for rebase/reviewer/test-runner agents — they enter the coordinator's existing worktree
