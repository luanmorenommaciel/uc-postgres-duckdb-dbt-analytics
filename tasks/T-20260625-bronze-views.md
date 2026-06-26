---
id: T-20260625-bronze-views
title: Bronze dbt views — lossless typing/standardize over raw.*
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: []
touches_paths:
  - transform/dbt_project.yml
  - transform/models/bronze
  - transform/models/sources.yml
source_note: sketch/duckdb-dbt-med-arch.plan
created: 0
tags: [dbt, bronze, medallion]
owner: (none)
priority: P1
severity: refactor
due_date: (none)
precondition: raw.* landed via `make land` (verified brownfield)
blocked_reason: (none)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: true
signed_off_by: luanmoreno
signed_off_at: 2026-06-26T01:39:35Z
---

# Bronze dbt views — lossless typing/standardize over raw.*

> **Why:** The medallion (Component A) needs a thin, non-destructive bronze layer that types and standardizes the four `raw.*` tables without dropping defect rows. It is the first dbt layer and unblocks silver; nothing above it can be built until raw is exposed as dbt sources with a clean, lossless bronze on top.

---

## Goal

Stand up the dbt project (DuckDB adapter, profile resolved from `DUCKDB_DATABASE` per the `src/warehouse` path rule) and ship one **bronze view per source table** (`bronze_customers/products/orders/payments`). Bronze trims/normalizes text (lowercase email, trim status) and carries `_ingested_at`, `_source_watermark`, and `_schema_drift` forward unchanged. It is **lossless**: row count equals `raw.*`, DECIMAL money is never recast, timestamps stay tz-aware. Defect rows (`negative_price`, `invalid_quantity`, `malformed_data`) pass through tagged, never deleted.

---

## Context

- Brownfield is GIVEN: `raw.raw_{customers,products,orders,payments}` exist with verified row parity (500/200/5000/5000). See `src/README.md`.
- Build order: **bronze (this) → silver → gold → API → MCP**. This is the first unit.
- The gold contract is owned by Component A; this task only establishes sources + bronze.
- dbt models are SQL, so the DuckDB `pytz`-on-materialize trap does not apply here (it bites Python consumers only).
- Bronze materializes as **views** (always fresh off raw, zero storage).

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: dbt project parses and bronze models build green against the warehouse
eval_1() {
  cd transform || return 1
  uv run dbt build --select "bronze" --quiet >/tmp/bronze_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/bronze_build.log
}

# eval-2: bronze is lossless — every bronze relation has the same row count as its raw.* source
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
pairs = [("raw.raw_customers","bronze.bronze_customers"),
         ("raw.raw_products","bronze.bronze_products"),
         ("raw.raw_orders","bronze.bronze_orders"),
         ("raw.raw_payments","bronze.bronze_payments")]
for raw, br in pairs:
    r = con.execute(f"SELECT count(*) FROM {raw}").fetchone()[0]
    b = con.execute(f"SELECT count(*) FROM {br}").fetchone()[0]
    assert r == b, f"row loss: {br}={b} vs {raw}={r}"
con.close()
PY
}

# eval-3: type fidelity preserved — orders money stays DECIMAL, timestamps stay tz-aware
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
types = dict(con.execute("""
  SELECT column_name, data_type FROM information_schema.columns
  WHERE table_schema='bronze' AND table_name='bronze_orders'
""").fetchall())
assert types.get("total_amount","").upper().startswith("DECIMAL"), types.get("total_amount")
assert "TIME ZONE" in types.get("ordered_at","").upper(), types.get("ordered_at")
assert "TIME ZONE" in types.get("_ingested_at","").upper(), types.get("_ingested_at")
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: dbt project parses; bronze models build green
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 30
  - id: eval_2
    description: bronze is lossless — row-count parity with raw.* per table
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: type fidelity — DECIMAL money, tz-aware timestamps preserved
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
  output_artifacts: [transform/models/bronze]
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

(none — this task is additive: a new dbt project + bronze views. No `raw.*` or `src/` writes. `git checkout -- transform/` discards it cleanly.)

---

## Observability Hooks

- **Expected duration:** dbt build of 4 views, < 30s.
- **Key metric:** bronze row count == raw row count per table.
- **Alert condition:** any bronze view row count ≠ its raw source (row loss).
- **Log tail:** `/tmp/bronze_build.log`.

---

## Anti-Patterns

- **Don't drop or repair defect rows in bronze** — bronze is lossless typing only; cleaning is silver's job. Pass defects through tagged.
- **Don't recast money to FLOAT/DOUBLE** — DECIMAL must survive verbatim; casting silently loses cents. Carry `unit_price`/`total_amount`/`amount`/`cost` as-is.
- **Don't hardcode the warehouse path** — resolve via `DUCKDB_DATABASE` / the `src/warehouse` rule, never a literal `.duckdb` path.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (the verified brownfield — bronze reads `raw.*`, never alters it)
- `src/db/01_schema.sql`, `docker-compose.yml` (the Postgres source)

---

## Open Questions

(none — this task is fully specified)
