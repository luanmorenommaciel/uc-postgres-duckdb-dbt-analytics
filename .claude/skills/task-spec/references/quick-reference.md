# Task-Spec Quick Reference

> One-page cheatsheet for daily Task-Spec operations.
> See [index.md](index.md) for full KB navigation.

---

## Generate a new Task-Spec

```bash
# Required: slug, effort (S or M)
# Optional: agent (default: any), source_note
bash ~/.claude/skills/task-spec/scripts/generate-task-spec.sh \
    verify-langfuse-otel S any notes/2026-05-04.md
```

## Validate before commit

```bash
bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh tasks/T-*.md
```

## Status transitions (atomic)

```bash
bash ~/.claude/skills/task-spec/scripts/transition-status.sh T-XXX in-progress
bash ~/.claude/skills/task-spec/scripts/transition-status.sh T-XXX done
bash ~/.claude/skills/task-spec/scripts/transition-status.sh T-XXX parked "budget exhausted"
```

## List ready tasks

```bash
bash ~/.claude/skills/task-spec/scripts/list-ready.sh
bash ~/.claude/skills/task-spec/scripts/list-ready.sh --effort=S
bash ~/.claude/skills/task-spec/scripts/list-ready.sh --agent=any
```

## Recovery

```bash
# Rebuild _state.yaml from frontmatter (truth)
bash ~/.claude/skills/task-spec/scripts/rebuild-state.sh

# Move done/parked to subdirs
bash ~/.claude/skills/task-spec/scripts/archive.sh

# Snapshot the backlog
bash ~/.claude/skills/task-spec/scripts/backup-backlog.sh
```

---

## YAML frontmatter — required fields

```yaml
---
id: T-YYYYMMDD-kebab-slug
title: One-line imperative
status: ready                  # ready | in-progress | blocked | done | parked
effort: S                      # S | M (L/XL refused; route to AgentSpec)
budget_iterations: 15
agent: any                     # any | python-developer | ...
depends_on: []
touches_paths:
  - path/to/file
source_note: notes/...md
created: 2026-05-19T00:00:00Z
tags: [...]
---
```

---

## The 4 zones

```text
Zone 1: ## Goal + ## Context        (lean, ≤100 lines)
Zone 2: ## Success Criteria         (≥3 runnable bash evals)
        ## Validation Card          (YAML mirror)
        ## Exit Check               (combined bash one-liner)
Zone 3: ## Anti-Patterns            (specific don'ts)
        ## Do-Not-Touch             (exact paths)
Zone 4: ## Open Questions           (admit unknowns)
```

---

## Eval pattern reminders

```bash
# Cheapest first; fail fast
eval_1() { test -f path/to/file; }           # presence  (1ms)
eval_2() { grep -q "thing" path/to/file; }   # content   (10ms)
eval_3() { curl -fs http://x | jq -e '.ok'; }# behavior  (500ms)
eval_4() { pytest -q tests/path; }           # tests     (30s)
```

---

## Routing rules

| Task is... | Use |
|------------|-----|
| S or M effort, bash-checkable success | **Task-Spec (EDD)** |
| L or XL effort | AgentSpec (SDD) |
| Subjective output (UI feel, copy) | AgentSpec (SDD) |
| One-off exploration ("what would X look like?") | Just prompt; no spec needed |

---

## v2 / v3 roadmap (deferred concepts)

**v2** will add:
- `budget_usd`, `budget_time` (cost ceilings)
- `isolation_class` (worktree / branch / shared)
- `schedulability` (parallel-safe / serial-after)
- `circuit_breaker` (explicit field)
- `precondition` (external blockers)
- `assumptions` (preconditions assumed true)
- `rollback_plan` (recovery doc)
- `observability_emit` (what to log)

**v3** will add:
- `confidence_threshold` (per-task)
- `review_mode` (auto / human-review / dry-run)
- `decisions_deferred` (late binding)
- `escalation_path` (when to ask)
- `kb_citations` (link to project KB)
- `mcp_validation_stamp` (recency proof)
- `eval_determinism` (formal property check)
- `eval_explainability` (per-eval rationale)

v2.1 is stable. Future format changes will be additive (backward-compatible); see CHANGELOG.md.

---

## Anti-patterns (don't)

- ❌ Edit frontmatter directly — use `transition-status.sh`
- ❌ Author L/XL as Task-Spec — refused; use AgentSpec
- ❌ Skip evals for "simple" tasks — every spec needs ≥3
- ❌ Verbose Zone 1 (>100 lines Context) — you wrote a PRD
- ❌ Vague Zone 3 ("be careful") — be specific
- ❌ Print secrets in evals or do-not-touch — redact always
