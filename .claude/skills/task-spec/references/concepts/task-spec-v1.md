# Task-Spec — The Format Specification

> **Current version:** v2.1 (stable)
> **First published:** 2026-05-19 (v1)
> **Format Owner:** task-spec CAW
> **Adopters:** anthive, taskship, AgentSpec, overnight-builder, Claude /goal, Codex, Kimi

The atomic, vendor-portable, self-verifying unit of work for autonomous agentic systems.

> **Note:** This document is the living format spec. It retains the `task-spec-v1.md`
> filename for link stability but describes the **current v2 format**. See the
> Version History section at the end for what changed across v0 → v1 → v2.

---

## What is Task-Spec?

A **Task-Spec** is a markdown file that fully specifies one PR's worth of work
in a format any agentic tool can pick up and execute. It carries its own
verification rules — agents don't need humans to tell them whether they
succeeded.

The format has **five non-negotiable properties**:

1. **Atomic** — one Task-Spec = one PR's worth of work (S/M effort only)
2. **Vendor-portable** — works in Claude, Codex, Kimi, Cursor, manual execution
3. **Self-verifying** — runnable bash evals declare "done" mechanically
4. **Pickupable** — fully specified at authoring time; no further input needed
5. **Reportable** — machine-checkable pass/fail emit

A Task-Spec fails to be a Task-Spec if it lacks any of these. That's enforced by `validate-task-spec.sh`.

The **canonical anatomy** is the six-zone structure — see [six-zones.md](six-zones.md)
for the zone-by-zone deep dive. The v2 `agent_contract` schema (cross-vendor, with
`required_tools` / `timeout_minutes` / `sandbox_type`) is documented in
[agent-contract.md](agent-contract.md).

---

## File anatomy

A Task-Spec is a single markdown file:

```text
tasks/T-YYYYMMDD-<slug>.md
```

Composed of **YAML frontmatter + 4 zones**:

```text
┌─ YAML FRONTMATTER ─────────────────────────────────────┐
│ Machine-parseable metadata                              │
└────────────────────────────────────────────────────────┘
┌─ ZONE 1 — INTENT ──────────────────────────────────────┐
│ Why this task exists (lean, ~100 lines max)             │
└────────────────────────────────────────────────────────┘
┌─ ZONE 2 — CONTRACT (the moat) ─────────────────────────┐
│ Runnable success criteria + validation card + exit     │
│ check + agent output contract                          │
└────────────────────────────────────────────────────────┘
┌─ ZONE 3 — GUARDRAILS ──────────────────────────────────┐
│ Anti-patterns, do-not-touch list                       │
└────────────────────────────────────────────────────────┘
┌─ ZONE 4 — OPERATIONS ──────────────────────────────────┐
│ Open questions, deferred decisions                     │
└────────────────────────────────────────────────────────┘
```

Every Task-Spec MUST have all 4 zones. Empty zones are allowed (use `(none)`),
omitted zones are a validation error.

---

## YAML Frontmatter — Required Fields

```yaml
---
id: T-20260519-verify-langfuse-otel
title: Verify self-hosted Langfuse stack ingests anthive OTEL traces end-to-end
status: ready
effort: S
budget_iterations: 15
agent: any
depends_on: []
touches_paths:
  - docs/observability-runbook.md
  - docker/langfuse-compose.yml
source_note: notes/2026-05-04-observability-handoff.md
created: 2026-05-19T00:00:00-0300
tags: ["observability", "verification", "langfuse"]
---
```

### Field reference

| Field | Type | Required | Validation rule |
|-------|------|----------|-----------------|
| `id` | string | yes | Format: `T-YYYYMMDD-<kebab-slug>`. Deterministic, unique within `tasks/`. |
| `title` | string | yes | Single line, ≤120 chars. Imperative voice preferred ("Verify X" not "Verifying X"). |
| `status` | enum | yes | One of: `ready`, `in-progress`, `blocked`, `done`, `parked`. |
| `effort` | enum | yes | One of: `S`, `M`. `L` and `XL` are REJECTED by the format (route to AgentSpec SDD instead). |
| `budget_iterations` | int | yes | Max retry cycles in the eval loop. Default 15. Hard cap 30. |
| `agent` | string | yes | `any` (vendor-portable) OR specific agent name (`python-developer`, `tsys-adf-parser`, etc.). |
| `depends_on` | list[string] | yes | List of Task-Spec IDs that must complete before this one. Empty `[]` if none. |
| `touches_paths` | list[string] | yes | Glob patterns of files this task WILL modify. Used for parallel-safety classification. |
| `source_note` | string | yes | Path to originating doc (meeting note, audit report). Provenance is non-optional. |
| `created` | ISO8601 | yes | Timestamp of authoring. Sortable, auditable. |
| `tags` | list[string] | no | Free-form labels for backlog navigation. |

Optional v1 fields:

| Field | Type | When to use |
|-------|------|-------------|
| `blocks` | list[string] | Inverse of `depends_on`; lists tasks blocked by this one |
| `source_action_item` | string | Specific item from `source_note` (e.g., "AI #6") |
| `precondition` | string | External event needed (not a task — e.g., "spec must be checked in") |
| `owner` | string | Human accountable for review |

---

## Zone 1 — Intent

```markdown
> **Why:** [1-2 sentences explaining why this task exists. Always present.]

## Goal

[One paragraph: what does success look like? Concrete, not aspirational.]

## Context

[Lean — max ~100 lines. Link to existing docs instead of duplicating.
This is NOT a PRD. Background only. The Contract zone does the heavy lifting.]
```

**Anti-pattern**: Verbose context dumps. If Zone 1 is longer than Zone 2, you've
written a PRD instead of a Task-Spec. Trim Zone 1; rely on Zone 2's evals to
specify behavior.

---

## Zone 2 — Contract (The Moat)

This is the zone that differentiates Task-Spec from every other task format.

```markdown
## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: stack starts cleanly
eval_1() {
  docker compose -f docker/langfuse-compose.yml up -d
  sleep 30
  test "$(docker ps --filter 'name=anthive-langfuse' --filter 'health=healthy' | wc -l)" -ge 1
}

# eval-2: UI reachable
eval_2() {
  curl -fs http://localhost:3000/api/public/health | jq -e '.status == "OK"'
}

# eval-3: real trace lands with expected attrs
eval_3() {
  python scripts/langfuse_smoke.py
}

# eval-4: runbook produced
eval_4() {
  test -f docs/observability-runbook.md && \
    grep -qi "first-time setup" docs/observability-runbook.md
}
```

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: Docker stack reaches healthy state
    runnable: bash
    terminal: true
    expected_duration_sec: 60
  - id: eval_2
    description: Langfuse UI reachable
    runnable: bash
    terminal: true
    expected_duration_sec: 5
  - id: eval_3
    description: Real OTEL trace lands with expected resource attributes
    runnable: bash
    terminal: true
    expected_duration_sec: 30
  - id: eval_4
    description: Runbook documents repeatable procedure
    runnable: bash
    terminal: true
    expected_duration_sec: 1

retry_policy:
  max_iterations: 15
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  read: [intent, contract, guardrails, operations]
  produce: code | docs | config | tests
  verify: run all success_criteria
  emit: pass | fail | retry_with_reason | parked_with_context
```

## Exit Check

```bash
# Final proof-of-done. Run as a single command; returns 0 only when task is complete.
eval_1 && eval_2 && eval_3 && eval_4
```
```

### Zone 2 field reference

| Field | Type | Required | Rule |
|-------|------|----------|------|
| `success_criteria` | bash functions | yes | At least 1, each must be terminal + idempotent |
| `validation_card.success_criteria` | YAML list | yes | One entry per bash function; descriptions in English |
| `validation_card.retry_policy` | YAML object | yes | max_iterations, circuit_breaker, on_terminal_failure |
| `validation_card.agent_contract` | YAML object | yes | read/produce/verify/emit declarations |
| `exit_check` | bash | yes | Single command combining all evals |

### Eval quality rules

1. **Terminal** — returns deterministically (no flaky network without retries)
2. **Idempotent** — running twice gives the same result
3. **Cheap before expensive** — order evals by cost; fail fast
4. **Explainable** — each eval has a one-line description WHY it exists
5. **Bash-portable** — no agent-specific tooling; standard POSIX where possible

---

## Zone 3 — Guardrails

```markdown
## Anti-Patterns

- **Don't [specific action]** — [reason]. [What to do instead].
- **Don't [specific action]** — [reason]. [What to do instead].

## Do-Not-Touch

Files the executor MUST NOT modify:

- `anthive/observability.py` — already implemented; this task verifies it
- `functions/adf/**` — auto-generated; will be regenerated by build-copy-src.sh
- `.env` — secrets layer; not the executor's concern
```

### Guardrail rules

| Rule | Why |
|------|-----|
| Anti-patterns must be SPECIFIC | "Be careful" is not a guardrail; "Don't edit auto-generated files" is |
| Do-not-touch lists EXACT paths | Globs allowed (`functions/adf/**`); vague descriptions rejected |
| Both sections are NON-OPTIONAL | If genuinely empty, write `(none)` — silence is rejected |

---

## Zone 4 — Operations

```markdown
## Open Questions

Things the executor should resolve DURING build, not assume:

1. **[Question]** — [why it matters, who to ask, fallback behavior]
2. **[Question]** — [why it matters]

## Rollback Plan (optional, v1)

[One paragraph: how to undo this task if it ships broken.]
```

Zone 4 admits unknowns up front. Honest tasks have open questions; dishonest
tasks pretend everything is known.

---

## Status Lifecycle

```text
    ┌─────────┐
    │  ready  │ ◄──────────────────┐
    └────┬────┘                    │
         │ executor claims         │ unblock
         ▼                         │
    ┌──────────────┐               │
    │ in-progress  │               │
    └──────┬───────┘               │
           │                       │
     ┌─────┴─────┬──────────┐      │
     ▼           ▼          ▼      │
  ┌──────┐  ┌────────┐  ┌────────┐ │
  │ done │  │ parked │  │blocked │─┘
  └──────┘  └────────┘  └────────┘
   evals     budget       waiting
   passed    exhausted    on dep
```

Status transitions are **atomic** — see `references/patterns/atomic-status-transitions.md`.

---

## Agent Contract (cross-vendor portability)

Any agent picking up a Task-Spec MUST honor this contract:

```yaml
on_pickup:
  - read: zones 1-4 in order
  - parse: validation_card YAML
  - acquire: lock via state-management layer

per_iteration:
  - execute: implementation (write code/docs/config)
  - run: all success_criteria as bash
  - emit: pass | fail | retry_with_reason
  - log: append to _metrics.jsonl

on_terminal_state:
  pass: transition status -> done; archive to tasks/done/
  budget_exhausted: transition status -> parked; archive to tasks/parked/
  unrecoverable_error: transition status -> blocked; do NOT archive
```

If an agent can't honor this contract, it can't consume Task-Spec. Period.

---

## File-system Conventions

```text
tasks/
├── T-20260519-foo.md           ← active backlog (status: ready | in-progress | blocked)
├── done/
│   └── T-20260518-bar.md       ← completed (status: done)
├── parked/
│   └── T-20260517-baz.md       ← budget-exhausted or blocked-with-context
├── _state.yaml                 ← derived index (REBUILDABLE from frontmatter)
└── _metrics.jsonl              ← append-only forensic ledger
```

State management rules in `references/concepts/backlog-architecture.md`.

---

## Versioning

Task-Spec follows semver:

- **v1.x** — additive changes only; v1 specs remain valid forever
- **v2.x** — breaking changes; will provide a v1 → v2 migration script
- **Format version is implicit in the schema** — no version field needed in the file itself

If you need to indicate which Task-Spec version a file conforms to, the
`task-spec` CAW's `validate-task-spec.sh` outputs the matched version.

---

## Compliance — When is a file a Task-Spec?

A markdown file is a valid Task-Spec v2.1 if and only if:

- [ ] YAML frontmatter present with all REQUIRED fields
- [ ] `effort` is `S` or `M` (not `L`/`XL`)
- [ ] Zone 1 has Goal + Context (Context may be terse but present)
- [ ] Zone 2 has ≥1 runnable bash success criterion
- [ ] Zone 2 has validation_card YAML
- [ ] Zone 2 has exit_check bash
- [ ] Zone 3 has Anti-Patterns + Do-Not-Touch (or explicit `(none)`)
- [ ] Zone 4 has Open Questions (or explicit `(none)`)
- [ ] No leftover `{{PLACEHOLDER}}` strings
- [ ] `touches_paths` references real or planned files
- [ ] `source_note` references an existing file

`validate-task-spec.sh` enforces all 11 rules.

---

## What Task-Spec is NOT

To prevent scope creep, here's what Task-Spec **deliberately excludes**:

| Excluded | Why | Where it lives instead |
|----------|-----|------------------------|
| Priority ordering | Executor concern | taskship's scheduler / anthive's queue |
| Parallel dispatch logic | Executor concern | anthive |
| PR creation | Executor concern | taskship/anthive both emit draft PRs |
| OTEL trace IDs | Executor concern | Whatever observability the executor uses |
| Cost ceilings (`budget_usd`) | v2 concern | Will be added in v2 |
| Cross-task dependencies as a DAG | Executor concern | `depends_on` field is enough for v1 |
| Multi-step plans within one task | Anti-pattern | Decompose into multiple Task-Specs |

Task-Spec is the FORMAT. Execution is someone else's job.

---

## Reference — A complete minimal example

```markdown
---
id: T-20260519-add-health-endpoint
title: Add /health endpoint to api server
status: ready
effort: S
budget_iterations: 10
agent: any
depends_on: []
touches_paths:
  - src/api/server.py
  - tests/test_health.py
source_note: notes/2026-05-19-monitoring-followups.md
created: 2026-05-19T14:00:00-0300
tags: ["api", "monitoring"]
---

> **Why:** Load balancer health checks fail because there's no /health endpoint.

## Goal

Add a `/health` endpoint returning `{"status":"ok"}` with HTTP 200 to the api server.

## Context

The api server is FastAPI-based at `src/api/server.py`. No existing health
endpoint exists. The k8s probes documented in `infra/k8s/api.yaml` already
reference `/health` (currently 404).

## Success Criteria

```bash
eval_1() {
  # Server starts cleanly
  uvicorn src.api.server:app --port 8001 &
  SERVER_PID=$!
  sleep 2
  test -d /proc/$SERVER_PID 2>/dev/null || ps -p $SERVER_PID > /dev/null
}

eval_2() {
  # /health returns 200 with {"status":"ok"}
  curl -fs http://localhost:8001/health | jq -e '.status == "ok"'
}

eval_3() {
  # Test exists and passes
  pytest tests/test_health.py -q
}
```

## Validation Card

```yaml
success_criteria:
  - {id: eval_1, description: "Server starts cleanly", runnable: bash, terminal: true}
  - {id: eval_2, description: "/health returns 200 + correct JSON", runnable: bash, terminal: true}
  - {id: eval_3, description: "Test for /health passes", runnable: bash, terminal: true}

retry_policy:
  max_iterations: 10
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  read: [intent, contract, guardrails, operations]
  produce: code + tests
  verify: run all success_criteria
  emit: pass | fail | retry_with_reason
```

## Exit Check

```bash
eval_1 && eval_2 && eval_3 && kill $SERVER_PID 2>/dev/null; true
```

## Anti-Patterns

- **Don't add liveness/readiness logic** — this is the simplest possible health check; depth comes later.
- **Don't add auth** — health endpoints are public by k8s convention.

## Do-Not-Touch

- `infra/k8s/api.yaml` — already references the correct path; no change needed.

## Open Questions

(none — this task is fully specified)
```

That's a complete, valid Task-Spec v2.1. ~80 lines. Any agent can pick it up.

---

## Why this format won

Task-Spec v2.1 won the design space because of one insight:

> **Specs that verify themselves don't need humans in the middle of the loop.**

Every other task format on the market is **readable** — humans interpret it,
agents interpret it, success is judged by humans interpreting outputs. Task-Spec
makes the success criteria **executable**. Now the spec carries its own
verification. The human only enters at intent (front) and PR review (back).

This is the same conceptual leap as:

- TDD (tests come first, code is judged by them)
- Infrastructure-as-code (config is executable, not described)
- Data contracts in DBT (data quality assertions ARE the spec)
- Type systems (types are checked, not asserted in prose)

Task-Spec is **Eval-Driven Development for agentic tasks** — the next step in
that lineage.

---

## Version History

| Version | What it added |
|---------|---------------|
| **v0** (legacy) | Pre-format tasks: markdown checklists, no runnable evals, effort L/XL allowed. Tolerated by the validator under the layered policy (warns, never hard-fails). Migrate via `migrate-legacy-task.sh`. |
| **v1** (2026-05-19) | Four zones (Intent / Contract / Guardrails / Operations), runnable bash evals, validation_card YAML, pipe-delimited `agent_contract`, frontmatter id/status/effort/budget/agent/touches_paths. |
| **v2** (current) | Six zones (adds **Rollback Plan** + **Observability Hooks**); cross-vendor `agent_contract` schema (`produce` as list, `emit` enum, `required_tools`, `timeout_minutes`, `sandbox_type`, vendor metadata blocks); accountability frontmatter (`owner`, `priority`, `severity`, `due_date`, `precondition`); severity-scaled quality thresholds; `creates_paths` for greenfield tasks. |

The validator accepts all three via `format_version` (default 1 if absent, 0 = legacy).
v2 specs declare `format_version: 2`.

---

## See also

- [eval-driven-development.md](eval-driven-development.md) — the methodology
- [edd-vs-sdd-honest-comparison.md](edd-vs-sdd-honest-comparison.md) — when EDD wins, when SDD wins
- [six-zones.md](six-zones.md) — zone-by-zone deep dive (the canonical anatomy)
- [effort-gate.md](effort-gate.md) — S/M/L/XL rules
- [agent-contract.md](agent-contract.md) — cross-vendor contract details
- [backlog-architecture.md](backlog-architecture.md) — 5-layer state management
- [../patterns/runnable-bash-evals.md](../patterns/runnable-bash-evals.md) — eval writing patterns
- [../patterns/validation-card-yaml.md](../patterns/validation-card-yaml.md) — YAML contract patterns
