---
id: T-20260625-gold-freshness
title: gold_freshness mart — event_to_reportable_lag (event watermark vs _ingested_at)
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-silver-conform]
touches_paths:
  - transform/models/gold
source_note: sketch/duckdb-dbt-med-arch.plan
created: 3
tags: [dbt, gold, freshness, E3]
owner: (none)
priority: P1
severity: bugfix
due_date: (none)
precondition: silver conformed (T-20260625-silver-conform signed off)
blocked_reason: (none)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# gold_freshness mart — event_to_reportable_lag (event watermark vs _ingested_at)

> **Why:** Spec E3 asks for **event-to-reportable lag** (minutes, not hours). `_ingested_at` alone measures land cadence — it advances every rebuild even when source events are old or late-arriving, so it can report "fresh" while the data is stale. The freshness surface must compare the newest business event against the ingest instant, or E3 is falsely green.

---

## Goal

Ship `gold.gold_freshness` carrying BOTH clocks per entity (+ a rollup row): `max(_ingested_at)` (batch clock), `max(<event_ts>)` (event clock — `max(ordered_at)`, `max(paid_at)`, `max(created_at)`, sourced from the `_source_watermark` stamp), and the derived `event_to_reportable_lag = _ingested_at − max(<event_ts>)`. The lag is the real E3 metric, compared against a pinned p95 window (default ≤5 min). A late-arriving/stalled source must surface as a growing lag, not a false-fresh rebuild. Include a dbt test that fails when a synthetic stale event would be reported as fresh.

---

## Context

- Every `raw.*` row already carries `_source_watermark` (the event high-watermark) and `_ingested_at` — both are tz-aware and carried bronze→silver→gold.
- Codex C1 (critical): the prior plan anchored E3 on `_ingested_at` alone → false-fresh on late arrival. This unit is the fix.
- The freshness mart is an **instrument**, not a business question — it's the E3 measurement surface the API `/freshness` reads.
- Sibling to `gold-marts` (separate unit so the freshness clock has its own eval). Both depend on silver.
- Build order: bronze → silver → **gold (this)** → API → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: gold_freshness builds green
eval_1() {
  cd transform || return 1
  uv run dbt build --select "gold_freshness" --quiet >/tmp/freshness_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/freshness_build.log
}

# eval-2: the mart carries BOTH clocks and the derived lag column (not just _ingested_at)
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
cols = {r[0] for r in con.execute("""
  SELECT column_name FROM information_schema.columns
  WHERE table_schema='gold' AND table_name='gold_freshness'
""").fetchall()}
need = {"max_ingested_at","max_event_ts","event_to_reportable_lag"}
missing = need - cols
assert not missing, f"gold_freshness missing required columns: {missing}"
con.close()
PY
}

# eval-3: lag is computed as ingest - event (non-negative; equals the difference of the two clocks)
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
rows = con.execute("""
  SELECT
    CAST(event_to_reportable_lag AS VARCHAR),
    CAST(date_diff('second', max_event_ts, max_ingested_at) AS VARCHAR)
  FROM gold.gold_freshness
  WHERE max_event_ts IS NOT NULL AND max_ingested_at IS NOT NULL
""").fetchall()
assert rows, "gold_freshness produced no comparable rows"
for lag_text, diff_secs in rows:
    # lag must reflect ingest-minus-event, i.e. a non-negative span when ingest >= event
    assert int(diff_secs) >= 0, f"event clock ahead of ingest clock (diff={diff_secs}s) — wrong direction"
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: gold_freshness builds green
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 20
  - id: eval_2
    description: mart carries both clocks + event_to_reportable_lag
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: lag = ingest - event, non-negative, correct direction
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
  output_artifacts: [transform/models/gold/gold_freshness.sql]
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

(none — additive: one new gold model + test. `git checkout -- transform/models/gold/gold_freshness.sql` discards it.)

---

## Observability Hooks

- **Expected duration:** single-mart build, < 20s.
- **Key metric:** `event_to_reportable_lag` p95 vs the pinned window (default ≤5 min).
- **Alert condition:** lag exceeds the window; lag computed from `_ingested_at` alone (event clock missing).
- **Log tail:** `/tmp/freshness_build.log`.

---

## Anti-Patterns

- **Don't define freshness as `now() − _ingested_at`** — that measures rebuild recency, not event-to-reportable lag. Compare against the event watermark.
- **Don't drop the per-entity grain** — a stalled `payments` source must be visible even if `orders` is fresh; a single rollup row hides it.
- **Don't materialize tz-aware timestamps into Python without casting** — DuckDB needs `pytz` to do that; cast to VARCHAR/epoch at the SQL boundary (the verified brownfield trap).

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (brownfield — the `_source_watermark` / `_ingested_at` stamps are the fixture)
- `transform/models/silver/**`, `transform/models/bronze/**` (upstream)

---

## Open Questions

1. **Freshness p95 window** — pin the number (default ≤5 min, p95). Owner: VP Data / CTO (spec §6). Default holds; does not block build.
