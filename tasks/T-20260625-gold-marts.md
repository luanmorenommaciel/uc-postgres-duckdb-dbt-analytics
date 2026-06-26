---
id: T-20260625-gold-marts
title: Gold dbt marts + per-mart schema.yml contract (owned by Component A)
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-silver-conform]
touches_paths:
  - transform/models/gold
source_note: sketch/duckdb-dbt-med-arch.plan
created: 2
tags: [dbt, gold, medallion, contract]
owner: (none)
priority: P1
severity: financial-critical
due_date: (none)
precondition: silver conformed (T-20260625-silver-conform signed off); E4 question set frozen
blocked_reason: gold mart list + grain gated on the frozen E4 question set (VP Data, spec §6)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# Gold dbt marts + per-mart schema.yml contract (owned by Component A)

> **Why:** Gold is the serving contract. It pre-aggregates silver into business marts shaped to the frozen E4 questions and ships a per-mart `schema.yml` — the versioned interface Component B (API/MCP) compiles against. If the contract is implicit, the serving layer binds to columns dbt never produces. Money flows through these aggregates, so correctness is financial-critical.

---

## Goal

Ship the gold marts as **tables** with an explicit, tested `schema.yml` per mart (column names, types, nullability, grain) — this is the contract Component A **owns** and B consumes. Marts: `gold_revenue_by_category` (category × day), `gold_customer_segments` (customer/segment, LTV), `gold_order_health` (day, status-rates derived via the pinned status→health map — `delivered`⇒fulfilled etc., NOT a raw `fulfilled` status), `gold_payment_reconciliation` (day, paid vs order total, refund/orphan). Each mart reconciles to silver (sum-of-mart = sum-of-source), has no NULL measures, and is covered by a committed `schema.yml`. (`gold_freshness` and atomic `_gold_run_id` are separate units.)

---

## Context

- The exact mart list and grain are **gated on the frozen E4 question set** (spec §6, owner VP Data) — `blocked_reason` records this. The marts below are the candidate set.
- Gold reads **silver only** via `ref()` — never bronze, raw, or Postgres.
- Status→health mapping is applied here (gold), defined against the pinned silver vocab (placed/shipped/delivered/returned/cancelled).
- The `schema.yml` IS the seam: a column is not consumable by B until declared here with a type. Codex C3.
- Build order: bronze → silver → **gold (this)** → API → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: gold builds and gold dbt schema tests pass (the schema.yml contract is enforced)
eval_1() {
  cd transform || return 1
  uv run dbt build --select "gold,exclude:gold_freshness" --quiet >/tmp/gold_build.log 2>&1 \
    || uv run dbt build --select "gold" --quiet >/tmp/gold_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/gold_build.log
}

# eval-2: every gold mart ships a schema.yml contract declaring its columns (the seam exists)
eval_2() {
  local sy=transform/models/gold/schema.yml
  test -f "$sy" || return 1
  for m in gold_revenue_by_category gold_customer_segments gold_order_health gold_payment_reconciliation; do
    grep -q "$m" "$sy" || { echo "missing contract for $m"; return 1; }
  done
}

# eval-3: revenue mart reconciles to silver (no rows lost/double-counted) and has no NULL measures
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
mart = con.execute("SELECT CAST(coalesce(sum(revenue),0) AS VARCHAR) FROM gold.gold_revenue_by_category").fetchone()[0]
src  = con.execute("""
  SELECT CAST(coalesce(sum(total_amount),0) AS VARCHAR)
  FROM silver.silver_orders WHERE status <> 'cancelled'
""").fetchone()[0]
assert mart == src, f"revenue mart {mart} != silver source {src}"
nulls = con.execute("SELECT count(*) FROM gold.gold_revenue_by_category WHERE revenue IS NULL").fetchone()[0]
assert nulls == 0, f"{nulls} NULL revenue measures in gold"
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: gold builds; gold dbt schema tests pass
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 45
  - id: eval_2
    description: per-mart schema.yml contract exists for all four marts
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 5
  - id: eval_3
    description: revenue mart reconciles to silver; no NULL measures
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
  output_artifacts: [transform/models/gold]
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

(none — additive: new gold models + schema.yml under `transform/models/gold`. `git checkout -- transform/models/gold` discards it; silver/bronze/raw untouched.)

---

## Observability Hooks

- **Expected duration:** gold build + schema tests, < 60s.
- **Key metric:** mart-to-silver reconciliation per mart.
- **Alert condition:** reconciliation mismatch; NULL measure; a column consumed by B absent from `schema.yml`.
- **Log tail:** `/tmp/gold_build.log`.

---

## Anti-Patterns

- **Don't let B define gold columns** — the contract lives here in `schema.yml`. Build the serving surface against this, not an independently-written column list.
- **Don't emit a raw `fulfilled` status** — apply the pinned status→health map; the rate is derived, the status value is not.
- **Don't read silver's quarantine tables into business marts** — gold aggregates the *clean* conformed tables; quarantined rows are excluded by design.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (brownfield)
- `transform/models/silver/**`, `transform/models/bronze/**` (upstream; consume via `ref()`)

---

## Open Questions

1. **Frozen E4 question set** — fixes the final mart list and grain. Owner: VP Data (spec §6). **Blocks completion of this task** (candidate marts buildable; final set gated).
2. **Order-health status map** — which statuses ⇒ fulfilled/in-flight/returned/cancelled rates. Owner: VP Data. Blocks `gold_order_health` only.
