# Runbook: Validating a Task-Spec

> **Use when:** Confirming a T-*.md is v2.1-compliant before commit or dispatch.

## The validator

```bash
bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh tasks/T-XXX.md
```

Exit codes:
- 0 — valid Task-Spec v2.1
- 1 — missing required fields or zones
- 2 — invalid field values
- 3 — leftover placeholders

## What it checks

1. YAML frontmatter exists and has all required fields
2. `effort` is `S` or `M` (rejects L/XL)
3. `status` is one of: ready/in-progress/blocked/done/parked
4. `id` matches `T-YYYYMMDD-<kebab-slug>` format
5. All 4 zones present (Goal, Context, Success Criteria, Validation Card, Exit Check, Anti-Patterns, Do-Not-Touch, Open Questions)
6. At least one `eval_N()` bash function in Success Criteria
7. Validation Card YAML has success_criteria + retry_policy + agent_contract
8. No leftover `{{TODO}}` or `{{PLACEHOLDER}}` strings

## When validation fails

| Failure | Fix |
|---------|-----|
| Missing frontmatter field | Add to YAML at top of file |
| Effort is L/XL | Decompose into multiple S/M tasks OR route to AgentSpec |
| Missing zone | Add the section header + content |
| No eval_N() functions | Write at least 3 runnable bash evals |
| Validation Card YAML missing | Add the YAML block under `## Validation Card` |
| Leftover `{{TODO}}` | Fill in the stub content |

## Pre-commit hook (optional)

Add to `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Validate any modified Task-Spec files
CHANGED=$(git diff --cached --name-only --diff-filter=ACM | grep '^tasks/T-.*\.md$' || true)
for f in $CHANGED; do
  bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh "$f" || exit 1
done
```

Prevents bad Task-Specs from entering git history.

## Bulk validation

```bash
# Validate every Task-Spec in the backlog
find tasks -name 'T-*.md' -exec \
  bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh {} \;
```

Useful before opening a PR with many task additions.
