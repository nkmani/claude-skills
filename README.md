# claude-skills

Personal collection of [Claude Code](https://claude.com/claude-code) skills.

Skills here are loaded by Claude Code via symlinks from `~/.claude/skills/`.
Edits should happen in this repo; the symlink keeps the live skill in sync.

## Layout

```
<skill-name>/
├── SKILL.md       # required: frontmatter + instructions to the agent
├── scripts/       # optional: helper scripts the skill shells out to
└── ...            # optional: REFERENCE.md, EXAMPLES.md, etc.
```

## Installing a skill

```bash
ln -snf ~/src/skills/<skill-name> ~/.claude/skills/<skill-name>
```

Restart any active Claude Code session for the new skill to appear in the
available-skills list. Edits to files under `~/src/skills/<skill-name>/`
take effect on the next skill invocation; no restart needed.

## Skills

### [`code-review-loop/`](code-review-loop/)

Two-agent implement/review ping-pong on a GitHub issue. Implementer Claude
Code session opens a PR and auto-spawns a reviewer in a new Terminal window;
reviewer polls via `/loop`, posts review comments with a `VERDICT:` sentinel,
and the implementer addresses feedback until the PR is approved and merged
(or hits the iteration cap).

Solo-author quirk: GitHub forbids `--approve` / `--request-changes` on your
own PRs, so the verdict is carried in the comment body as
`VERDICT: APPROVE` / `VERDICT: REQUEST_CHANGES` and `parse-verdict.sh` greps
for it.

See [`code-review-loop/SKILL.md`](code-review-loop/SKILL.md) for the full
contract.
