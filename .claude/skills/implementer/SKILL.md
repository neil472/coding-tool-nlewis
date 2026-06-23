---
name: implementer
description: Pure development workflow with test-first development and coverage review. Used by coordinator as a subagent. Commits to its own worktree branch, but never pushes, manages beads issues, or opens PRs.
---

# Implementer

Follow these phases **in strict order**. Do not skip phases. Do not proceed until the current phase's gate is satisfied.

This skill covers development through committing to your own worktree branch — no issue tracking, no pushing, no PRs. The coordinator handles those: it integrates your branch by rebasing your commits onto the feature branch (see Phase 5). Your work only survives integration if it is **committed** — uncommitted changes are discarded when the coordinator removes your worktree.

## Principles

- **Stay in your assigned worktree.** You can `cd` freely within it, but don't leave its root, and don't write to absolute paths outside it. Every worktree is a full repo — `bd`, `git`, `npm` all work from inside it.
- Never silently work around problems. Throw errors for missing env vars, invalid state, missing dependencies.
- Mock properly in tests. Do not add production fallbacks to make tests pass.
- No type casts that bypass the type system.
- No optional chaining on required properties.
- **Test cases from the issue are your spec.** The planner defines concrete test cases on each task. Implement those first, then add high-value coverage for gaps. Focus on tests that catch real bugs — avoid exhaustive, duplicative unit tests that test constructors, wiring, or things the compiler already guarantees.
- **Delegate quality gates to test-runner sub-agents.** Do NOT run `npm test`, `npm run lint`, or `npx tsc --noEmit` directly — their output consumes your context window. Use the Task tool to spawn a test-runner (see Phase 3). Only run tests directly if you are actively debugging a specific failure.
- **Lint and typecheck are run as part of the Phase 3 gate, not separately.** lefthook's pre-commit hook also enforces lint + typecheck on every commit, so don't run them ad hoc — the test-runner runs the full gate.
- **If a hook blocks a tool call, stop.** Never work around it with scripts, `sed`, or other indirect tricks. Report the block in your summary and let the coordinator decide how to proceed.

## Phase 1: Write Failing Tests

Implement the **test cases defined in the task issue** before touching production code. These are your acceptance criteria — they define what "done" looks like.

1. Read the task description (`bd show <task-id> --json`) and identify the test cases
2. Read the relevant production code to understand current behavior
3. Implement each specified test case
4. Add additional high-value tests for gaps you identify (error paths, edge cases) — but focus on quality over quantity. A few well-targeted tests beat many shallow ones.
5. Verify your new tests fail by delegating to a test-runner sub-agent (see Phase 3)

**Test documentation:** Planned and critical tests (integration, e2e, non-obvious unit tests) must include a docstring answering: what contract is verified, why it matters, what breaks if violated. Table-driven tests with descriptive names are often self-documenting — use judgment.

**Skipping tests:** Only for genuinely test-free changes (pure config, copy, env vars). Migrations, refactors, and wiring still need tests.

**Gate:** Your new tests **fail** (or, for pure deletions/removals, you can write tests asserting the old behavior is gone — these will pass after implementation). If your new tests already pass, they are not testing anything new. Rewrite them.

## Phase 2: Implement

Make the production code changes. Keep changes minimal and focused on the task.

## Phase 3: Verify

**Delegate quality gate runs to a test-runner sub-agent** to preserve your context window. Do NOT run these commands directly with the Bash tool — test output is verbose and wastes context you need for later phases. Use the Task tool with `subagent_type: "Bash"` and `model: "haiku"`:

```
ROLE: Test Runner
SKILL: Read and follow .claude/skills/test-runner/SKILL.md

WORKING DIRECTORY: <worktree-path>
COMMANDS:
- <test commands from the Quality Gates table in CLAUDE.md matching changed code>
```

**Run the gates for the code you changed:** `npm test` (always), `npm run lint`, `npx tsc --noEmit`, plus `npm run test:integration:sandbox` if the change touches the sandbox/server boundary. lefthook enforces lint + typecheck on pre-commit and `npm test` on pre-push, so commits/pushes are gated automatically — but run the gate explicitly here (via the test-runner) so failures surface before you hand back, not at commit time.

**Gate:** Sub-agent reports PASS. If FAIL, read the error summary, fix the issue, and re-delegate. Only run quality gates directly in your own context if you need to debug a failure interactively.

## Phase 4: Test Coverage Audit

Verify all planned test cases are implemented. Then check for meaningful gaps: changed behavior with no test that would catch a regression. Focus on real failure modes, not exhaustive coverage. If gaps exist, write targeted tests and re-run via test-runner.

**Gate:** All planned test cases implemented. No meaningful coverage gaps, or gaps documented with reasoning.

## Phase 5: Commit

Commit your work to your worktree branch. **Do not push** and **do not open a PR** — the coordinator integrates your branch by rebasing these commits onto the feature branch, so the work must be committed to survive.

```bash
git add -A
git commit -m "<type>: <concise description of the change>"
```

- Use a conventional-commit subject (`feat:`, `fix:`, `test:`, `refactor:`, etc.).
- lefthook's pre-commit hook runs lint + typecheck; a clean Phase 3 gate means this should pass. **If the pre-commit hook blocks the commit, stop** — do not bypass it with `--no-verify` or other tricks. Report the block in your summary.
- Stage everything you changed (new test files, production code). Don't leave intended changes uncommitted.

**Gate:** Your changes are committed on the worktree branch. Capture the full commit hash for the summary.

## Phase 6: Summary

**This must be the very last thing you output.** The coordinator reads your result — keep it concise to avoid polluting its context.

Produce exactly this and nothing else after it:

```
IMPLEMENTATION RESULT: SUCCESS | FAILURE

Task: <task-id or "N/A" if not provided>
Commit: <full commit hash, or "N/A" on failure>

## What changed
- <1 bullet per logical change, max 5>

## Files modified
- <path> — <what changed in 1 phrase>

## Test coverage
- <1 bullet per test file added/modified, what it covers>

## Concerns
- <anything the coordinator should know, or "None">
```

If implementation failed, replace "What changed" with:

```
## Error
<what went wrong — 1-3 sentences>

## Attempted
- <what you tried>
```
