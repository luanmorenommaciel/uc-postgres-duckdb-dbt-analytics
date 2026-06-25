# The Six Zones

> **Purpose**: Anatomy of a Task-Spec v2.1 file. Each zone has a specific job.
> **Confidence**: HIGH
> **MCP Validated**: 2026-05-19

A Task-Spec is YAML frontmatter + 6 zones. Every zone has a purpose; no zone is optional.

```text
┌─ YAML FRONTMATTER ─────────────────────────────────────────────┐
│ Machine-parseable metadata (required + optional fields)         │
├─ ZONE 1 — INTENT (why) ────────────────────────────────────────┤
│ Goal + Context. Lean. ≤100 lines.                              │
├─ ZONE 2 — CONTRACT (what + how to verify) ─────────────────────┤
│ Success Criteria + Validation Card + Exit Check                │
│ THE MOAT. The reason Task-Spec exists.                         │
├─ ZONE 3 — ROLLBACK (how to reverse) ───────────────────────────┤
│ Revert procedure if execution fails mid-task                   │
├─ ZONE 4 — OBSERVABILITY (what to watch) ───────────────────────┤
│ Expected duration, key metrics, alert conditions               │
├─ ZONE 5 — GUARDRAILS (what NOT to do) ─────────────────────────┤
│ Anti-Patterns + Do-Not-Touch list                              │
├─ ZONE 6 — OPERATIONS (admissions + recovery) ──────────────────┤
│ Open Questions                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Zone 1 — Intent

**Job**: Tell the agent WHY this task exists, briefly.

**Contents**:
- One-line `> **Why:**` callout
- `## Goal` — concrete success in one paragraph
- `## Context` — lean background, link to existing docs

**Anti-pattern**: verbose context dumps. Zone 1 longer than Zone 2 = wrote a PRD instead of a Task-Spec.

**Rule**: ≤100 lines for Context. Link to existing docs instead of duplicating.

## Zone 2 — Contract (THE MOAT)

**Job**: Define success mechanically. The agent's instruction set.

**Contents**:
- `## Success Criteria` — runnable bash evals (≥3, terminal, idempotent)
- `## Validation Card` — YAML mirror of the evals + retry policy + agent contract
- `## Exit Check` — combined bash one-liner

**Why this is the moat**: Every other task format in the world is *readable*.
Zone 2 makes the success criteria *executable*. Now the spec carries its own
verification. Without Zone 2, this isn't Task-Spec.

**Rule**: At least 3 evals. Ordered cheap-to-expensive. Each terminal + idempotent.

## Zone 3 — Rollback Plan

**Job**: Declare how to reverse the task if execution fails mid-flight.

**Contents**:
- `## Rollback Plan` — specific steps to restore pre-task state
- Git revert, file restore, state reset instructions
- Or `(none — this task is append-only or additive with no destructive changes)`

**Why this matters**: A spec without a rollback plan leaves the executor guessing
how to recover from partial failure. Zone 3 removes that ambiguity.

**Rule**: If genuinely empty, write `(none)` — silence is rejected by validation.

## Zone 4 — Observability Hooks

**Job**: Declare what to watch during execution and after deployment.

**Contents**:
- `## Observability Hooks` — expected duration, key metrics, alert conditions, log tails
- Or `(none — no runtime observability required)`

**Why this matters**: The validation_card has `expected_duration_sec`, but without
Zone 4 there is no mechanism to alert when execution exceeds it. Zone 4 makes
runtime expectations explicit.

**Rule**: If genuinely empty, write `(none)` — silence is rejected by validation.

## Zone 5 — Guardrails

**Job**: Bound the agent's scope.

**Contents**:
- `## Anti-Patterns` — specific "don'ts" with reasons
- `## Do-Not-Touch` — exact paths the agent must not modify

**Anti-pattern**: vague guidance ("be careful"). Anti-patterns must be SPECIFIC actions.

**Rule**: If genuinely empty, write `(none)` — silence is rejected by validation.

## Zone 6 — Operations

**Job**: Admit what's unknown; document recovery.

**Contents**:
- `## Open Questions` — things to resolve during build (not at authoring time)

**Why this matters**: Honest tasks have unknowns. Dishonest tasks pretend
everything is known. Zone 6 surfaces ambiguity instead of hiding it.

## Zone interactions

| Zone | Reads from | Influences |
|------|------------|-----------|
| 1 (Intent) | User input | Zones 2 and 5's framing |
| 2 (Contract) | Intent + MCP research | Agent's execution loop |
| 3 (Rollback) | Contract + blast radius | Recovery protocol on failure |
| 4 (Observability) | Contract + runtime surface | Alert thresholds and metrics |
| 5 (Guardrails) | MCP research + repo scan | Agent's blast radius |
| 6 (Operations) | Honest uncertainty | Where to ask human if loop stalls |

Zone 2 does the heavy lifting. Zones 1, 3, 4, 5, 6 are scaffolding that bounds,
contextualizes, and operationalizes Zone 2.

## Frontmatter accountability

The YAML frontmatter carries machine-parseable metadata:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | T-YYYYMMDD-<kebab-slug> |
| `title` | yes | Human-readable task name |
| `status` | yes | ready \| in-progress \| blocked \| done \| parked |
| `effort` | yes | S or M (L/XL → AgentSpec SDD) |
| `budget_iterations` | yes | Max retry iterations |
| `agent` | yes | Agent hint (any, python-developer, etc.) |
| `depends_on` | yes | List of blocking task IDs |
| `touches_paths` | yes | Files or globs the task modifies |
| `source_note` | yes | Provenance (audit, meeting, ticket) |
| `created` | yes | ISO-8601 timestamp |
| `tags` | yes | Taxonomy labels |
| `owner` | no | Accountable individual |
| `priority` | no | P0 (drop everything) → P4 (backlog) |
| `severity` | no | cosmetic \| refactor \| feature \| bugfix \| security \| financial-critical |
| `due_date` | no | YYYY-MM-DD |
| `precondition` | no | What must be true before starting |

Priority and severity are orthogonal:
- **Priority** describes urgency (P0 = now, P4 = someday)
- **Severity** describes consequence (financial-critical = high stakes regardless of urgency)

A P3 financial-critical task exists (low urgency, high stakes).
A P0 cosmetic task exists (high urgency, low stakes).

## Related

- [task-spec-v1.md](task-spec-v1.md) — full format spec with zone examples
- [eval-driven-development.md](eval-driven-development.md) — why Zone 2 is the moat
- [../patterns/runnable-bash-evals.md](../patterns/runnable-bash-evals.md) — Zone 2 eval writing
