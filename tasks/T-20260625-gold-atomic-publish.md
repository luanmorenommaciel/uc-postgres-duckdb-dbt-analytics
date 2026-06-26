---
id: T-20260625-gold-atomic-publish
title: Atomic gold publish — shared _gold_run_id across all marts
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-gold-marts, T-20260625-gold-freshness]
touches_paths:
  - transform/models/gold
  - transform/macros
source_note: sketch/duckdb-dbt-med-arch.plan
created: 4
tags: [dbt, gold, publish, consistency]
owner: (none)
priority: P1
severity: bugfix
due_date: (none)
precondition: gold marts + gold_freshness built
blocked_reason: (none)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# Atomic gold publish — shared _gold_run_id across all marts

> **Why:** Readers (the API/MCP layer) run concurrently with dbt. Without an atomic publish boundary, an in-progress dbt run can expose one refreshed mart next to a stale or half-replaced one — producing inconsistent cross-endpoint answers and incoherent freshness claims. A shared generation stamp lets readers bind to one fully-published version.

---

## Goal

Stamp every gold mart with a shared `_gold_run_id` (one value per dbt run, identical across all marts of that run) so the serving layer can read a single, consistent generation. After a full gold build, **all** gold marts carry the **same** `_gold_run_id`; a reader filtering to the latest fully-published id never sees a mixed-generation set. Ship a dbt test asserting the single-generation invariant.

---

## Context

- Codex C5 (high): the prior plan claimed "no serialization needed," which is true for single-mart file access but wrong for cross-mart consistency during a multi-table `CREATE OR REPLACE` run.
- DuckDB is single-writer-process; dbt is the only writer, serialized after `make land`. This unit adds the *generation* guarantee on top.
- The serving layer (`api-fastapi`, `mcp-tools`) consumes `_gold_run_id` to read the latest complete generation — that read-side contract is specified in those units.
- Implementation latitude: a run-id macro stamped into every mart, or a staging-then-swap publish. Either satisfies the invariant.
- Build order: bronze → silver → gold marts + freshness → **atomic publish (this)** → API → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: a full gold build completes green
eval_1() {
  cd transform || return 1
  uv run dbt build --select "gold" --quiet >/tmp/publish_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/publish_build.log
}

# eval-2: every gold mart carries a _gold_run_id column
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
marts = [r[0] for r in con.execute("""
  SELECT table_name FROM information_schema.tables WHERE table_schema='gold'
""").fetchall()]
assert marts, "no gold marts found"
for m in marts:
    cols = {r[0] for r in con.execute(f"""
      SELECT column_name FROM information_schema.columns
      WHERE table_schema='gold' AND table_name='{m}'
    """).fetchall()}
    assert "_gold_run_id" in cols, f"gold.{m} missing _gold_run_id"
con.close()
PY
}

# eval-3: all gold marts share ONE _gold_run_id (single published generation)
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
marts = [r[0] for r in con.execute("""
  SELECT table_name FROM information_schema.tables WHERE table_schema='gold'
""").fetchall()]
ids = set()
for m in marts:
    for (rid,) in con.execute(f"SELECT DISTINCT CAST(_gold_run_id AS VARCHAR) FROM gold.{m}").fetchall():
        ids.add(rid)
assert len(ids) == 1, f"mixed gold generations across marts: {ids}"
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: full gold build completes green
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 60
  - id: eval_2
    description: every gold mart carries _gold_run_id
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: all gold marts share one _gold_run_id (single generation)
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10

retry_policy:
  max_iterations: 15
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  version: 2
  read: [intent, contract, guardrails, operations]
  produce:
    - code
    - config
    - tests
  required_tools: [git, bash]
  timeout_minutes: 30
  sandbox_type: host
  output_artifacts: [transform/macros]
  mcp_dependencies: []
  emit:
    - pass
    - fail
    - retry_with_reason
    - parked_with_context
  codex_metadata: {}
  kimi_metadata: {}
```

---

## Exit Check

```bash
# Final proof-of-done. Returns 0 only when ALL evals pass.
eval_1 && eval_2 && eval_3
```

---

## Rollback Plan

(none — additive: a run-id macro/column on existing marts. `git checkout -- transform/` discards it; the marts rebuild without the stamp.)

---

## Observability Hooks

- **Expected duration:** full gold build, < 60s.
- **Key metric:** distinct `_gold_run_id` count across all gold marts == 1.
- **Alert condition:** more than one `_gold_run_id` visible (mixed generation); a mart missing the stamp.
- **Log tail:** `/tmp/publish_build.log`.

---

## Anti-Patterns

- **Don't claim read/write concurrency removes the need for a generation boundary** — file-level concurrency ≠ cross-mart consistency. The stamp is what makes a multi-mart read coherent.
- **Don't derive the run id per-mart** — it must be one value for the whole run, or the invariant is meaningless. Compute once, stamp everywhere.
- **Don't use `Math.random`/wall-clock inside dbt Jinja in a way that varies per model** — the id must be stable across all marts of a single run.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (brownfield)
- `transform/models/silver/**`, `transform/models/bronze/**` (upstream layers)

---

## Open Questions

(none — this task is fully specified)
