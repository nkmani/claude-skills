---
name: code-review-loop
description: Two-agent implement/review ping-pong on a GitHub issue. Implementer session opens a PR and auto-spawns a reviewer Terminal that polls for new pushes, posts inline review comments and a verdict, and the implementer addresses feedback until the PR is LGTM + merged or hits the iteration cap. Use when the user wants an autonomous code-and-review loop, says "ping-pong this issue", "implement with reviewer", or invokes /code-review-loop.
---

# code-review-loop

Autonomous implement ↔ review loop driven by two Claude Code sessions sharing a state file.

## Quick start

```
/code-review-loop implement <issue#>      # in current session — becomes the IMPLEMENTER
# auto-spawns a second Terminal window running:
/code-review-loop review <pr#>            # the REVIEWER, polling via /loop
```

The implementer does the work, pushes commits, and waits. The reviewer wakes every few minutes, sees new commits, reviews the PR, and writes a verdict (`APPROVE` or `REQUEST_CHANGES`) into the shared state file. The implementer reads the verdict on its next tick and either addresses comments or merges.

State file: `~/.claude/coderev-loop/<repo>/<pr>.json`.

## Modes

The first arg picks the role: `implement` or `review`. Second arg is the issue# (implementer) or PR# (reviewer).

### Implementer (`implement <issue#>`)

First invocation (no state file yet):
1. `gh issue view <issue#>` — read title, body, acceptance criteria
2. Create feature branch from `main` (or `dev-main` per project memory)
3. Write minimal first commit; push; open draft PR via `gh pr create`
4. Initialize state file via `scripts/state.sh init <pr> <issue> <branch> <max_iter>` (default `max_iter=10`)
5. Auto-spawn reviewer: `scripts/spawn-reviewer.sh <pr>` opens a new Terminal.app window running `claude` with `/loop 5m /code-review-loop review <pr>`
6. Continue implementing toward acceptance criteria; commit + push when a coherent slice is ready
7. Run `/loop 3m /code-review-loop implement <issue#>` to wait for verdicts

Subsequent ticks (state file exists):
- Read `status` and `last_verdict` via `scripts/state.sh get <pr>`
- `REQUEST_CHANGES`: pull reviewer's inline comments via `gh pr view --comments` + `gh api .../reviews/.../comments`; address each; commit + push; `state.sh set <pr> status implementing`
- `APPROVE` with `status != merged`: run pre-merge checks (`make test-py` or whatever the repo uses); `gh pr merge --squash --auto`; `state.sh set <pr> status merged`; **exit loop**
- `status == merged` or `iteration >= max_iterations`: print summary and **exit loop**
- Pending review (no new verdict since last push): noop, wait next tick

### Reviewer (`review <pr#>`)

Each /loop tick:
1. Check for new commits: `scripts/has-new-commits.sh <pr>` (compares head SHA to `last_reviewed_sha` in state)
   - No new commits → exit tick (next /loop fires in 5m)
2. Use the `review` skill to perform a full PR review (summary + findings).
3. Decide verdict: `APPROVE` if all acceptance criteria met, no blocking issues, tests pass; else `REQUEST_CHANGES`.
4. **Post via `--comment` with a verdict sentinel as the first line of the body.** GitHub refuses `--approve` / `--request-changes` on the PR author's own PRs (the solo-dev case), so the verdict is carried in the body, not in the GH review state. Format:

   ```
   VERDICT: APPROVE
   <blank line>
   <full review body — summary, findings, suggestions>
   ```

   or `VERDICT: REQUEST_CHANGES` for the other branch. The sentinel must be on its own line, anchored at the start, exact spelling. Post with:

   ```
   gh pr review <pr> --comment -F /tmp/pr<pr>-review.md
   ```
5. Parse own verdict and update state: `scripts/parse-verdict.sh <pr>` reads the latest review's `state` first; on `COMMENTED` it greps the body for the sentinel. Writes `last_verdict` + `last_reviewed_sha` + bumps `iteration`.
6. If verdict is `APPROVE` and merge happens externally → reviewer's next tick sees `status == merged` and exits the /loop.

## Stopping conditions

The loop ends on **any** of:
- Reviewer posts `APPROVE` **and** implementer successfully merges
- `iteration >= max_iterations` (default 10) — implementer writes `status: failed` and stops
- User manually stops either session

## Scripts

- `scripts/state.sh {init,get,set} <pr> [field] [value]` — atomic state file r/w
- `scripts/has-new-commits.sh <pr>` — exits 0 if PR head SHA differs from `last_reviewed_sha`
- `scripts/parse-verdict.sh <pr>` — reads latest review on PR, writes verdict + SHA into state
- `scripts/spawn-reviewer.sh <pr>` — osascript opens new Terminal.app window running the reviewer

## Conventions

- Both sessions run in the **same working tree** (state file coordinates; reviewer reads via `gh pr diff`, never checks out)
- Branch base: `main` (or `dev-main` for `~/src/trading/yafts-dev` worktrees — check `[[feedback_dev_main_branch]]`)
- Reviewer **never pushes commits** — only review comments
- Implementer **never edits state's verdict field** — only `status`, `iteration` (on push)
- If state file is stale (PR closed, branch gone), implementer prints a recovery message and exits — never auto-deletes

## Autonomy contract

**Invoking this skill is consent to its documented side effects.** Inside a tick, do NOT prompt the user before:

- `gh pr review <pr> --comment -F …` (reviewer posting its verdict comment)
- `gh pr merge --squash --auto` (implementer auto-merging after `APPROVE`)
- `git push` on the implementer's PR branch
- `state.sh set …` writes

These are the whole point of the loop; per-tick confirmation defeats it. The general "ask before shared-state changes" default in the system prompt is overridden by the explicit `/loop /code-review-loop …` invocation. Still ask the user before:

- Force-pushing, deleting the branch, closing the PR
- Editing files outside the implementer's branch scope
- Anything the skill doesn't already describe

## Failure modes

- `gh` not authed → hard error on first call; user must `gh auth login`
- Reviewer spawns but no Terminal.app (e.g. SSH session) → `spawn-reviewer.sh` falls back to printing the command for manual paste
- Two reviewer windows accidentally launched → second one sees `status == in_review` recently bumped and exits its tick
- Reviewer forgets the `VERDICT:` sentinel on a solo-author PR → `parse-verdict.sh` defaults to `REQUEST_CHANGES`; loop never approves until a sentinel-bearing comment lands. Multi-author repos can ignore this and use real `--approve` / `--request-changes`, which `parse-verdict.sh` honors first.

See [scripts/](scripts/) for implementation details.
