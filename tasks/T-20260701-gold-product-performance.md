---
id: T-20260701-gold-product-performance
title: Gold dbt mart — product performance (product×day) + per-mart schema.yml contract
status: ready
format_version: 2
effort: S
budget_iterations: 15
agent: any
depends_on: [T-20260625-silver-conform]
creates_paths:
  - transform/models/gold
touches_paths:
  - transform/models/gold
source_note: sketch/duckdb-dbt-med-arch.plan
created: 7
tags: [dbt, gold, medallion, contract]
owner: (none)
priority: P2
severity: financial-critical
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

# Gold dbt mart — product performance (product×day) + per-mart schema.yml contract

> **Why:** Per-SKU performance (units, revenue, margin per product per day) is a first-class serving question the current gold set does not answer — `gold_revenue_by_category` rolls up to category and loses the per-product view merchandisers and buyers need. This mart adds that grain over the **conformed silver** tables and ships its own `schema.yml` contract so Component B binds to a declared interface. Revenue and margin are money, so correctness is financial-critical.

---

## Goal

Ship one additive gold mart, `gold_product_performance`, as a **table** at grain **(product_id, order_date)** with measures `units_sold`, `gross_revenue` (DECIMAL), `gross_margin` (DECIMAL = revenue − cost×quantity), and `orders_count`. It reads **silver only** via `ref('silver_orders')` / `ref('silver_products')`, excludes `cancelled` orders (realized sales only), carries `_gold_run_id` to participate in atomic publish (R5), and is covered by a committed per-mart `schema.yml` (columns, types, grain). It reconciles to silver (sum-of-mart revenue = sum-of-source), has a unique grain, and no NULL measures. This does **not** duplicate the four marts in `T-20260625-gold-marts` — it is a distinct product-grain unit.

---

## Context

- **Gold reads silver only via `ref()`** — never bronze, raw, or Postgres (R2; mirrors `gold_revenue_by_category`). Reading `raw.*` would skip bronze typing and silver cleaning, landing the 14 injected defects into a money mart.
- Additive **sibling** to `T-20260625-gold-marts`; the two share `transform/models/gold/schema.yml` (append this mart's contract, don't rewrite the others'). The data dependency is silver, so `depends_on` is silver-conform — same as gold-marts.
- Money stays **DECIMAL** end-to-end; timestamps stay tz-aware. dbt models are SQL, so the DuckDB `pytz`-on-materialize trap does not bite here; the reconciliation eval CASTs money to VARCHAR at the SQL boundary so the Python check compares exact strings, not floats.
- Must carry **`_gold_run_id`** so it publishes atomically with the other marts (R5). The atomic-publish mechanism itself is `T-20260625-gold-atomic-publish`, a separate unit.
- Order status vocab is `placed/shipped/delivered/returned/cancelled` — there is **no raw `fulfilled` status**. This mart does not derive health rates (that is `gold_order_health`); it excludes only `cancelled`.
- Build order: bronze → silver → **gold (this)** → API → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: the mart builds and its gold dbt schema tests pass (the schema.yml contract is enforced)
eval_1() {
  cd transform || return 1
  uv run dbt build --select "gold_product_performance" --quiet >/tmp/gold_product_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/gold_product_build.log
}

# eval-2: the mart ships a schema.yml contract declaring its grain + measure columns (the seam exists)
eval_2() {
  local sy=transform/models/gold/schema.yml
  test -f "$sy" || return 1
  grep -q "gold_product_performance" "$sy" || { echo "missing contract for gold_product_performance"; return 1; }
  for c in product_id order_date units_sold gross_revenue gross_margin; do
    grep -q "$c" "$sy" || { echo "missing column $c in contract"; return 1; }
  done
}

# eval-3: reconciles to silver; grain is unique; no NULL measures; money stays DECIMAL
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()

# reconcile: mart revenue == silver non-cancelled order revenue (VARCHAR keeps DECIMAL exact)
mart = con.execute(
    "SELECT CAST(coalesce(sum(gross_revenue),0) AS VARCHAR) FROM gold.gold_product_performance"
).fetchone()[0]
src = con.execute("""
  SELECT CAST(coalesce(sum(total_amount),0) AS VARCHAR)
  FROM silver.silver_orders WHERE status <> 'cancelled'
""").fetchone()[0]
assert mart == src, f"revenue mart {mart} != silver source {src}"

# grain uniqueness: exactly one row per (product_id, order_date)
dupes = con.execute("""
  SELECT count(*) FROM (
    SELECT product_id, order_date
    FROM gold.gold_product_performance
    GROUP BY product_id, order_date HAVING count(*) > 1
  )
""").fetchone()[0]
assert dupes == 0, f"{dupes} grain duplicates in gold_product_performance"

# no NULL measures
nulls = con.execute("""
  SELECT count(*) FROM gold.gold_product_performance
  WHERE gross_revenue IS NULL OR gross_margin IS NULL OR units_sold IS NULL
""").fetchone()[0]
assert nulls == 0, f"{nulls} NULL measures in gold_product_performance"

# money fidelity: revenue + margin stay DECIMAL, never float
types = dict(con.execute("""
  SELECT column_name, data_type FROM information_schema.columns
  WHERE table_schema='gold' AND table_name='gold_product_performance'
""").fetchall())
assert types.get("gross_revenue","").upper().startswith("DECIMAL"), types.get("gross_revenue")
assert types.get("gross_margin","").upper().startswith("DECIMAL"), types.get("gross_margin")
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: gold_product_performance builds; its gold dbt schema tests pass
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 30
  - id: eval_2
    description: per-mart schema.yml declares grain + measure columns (the seam exists)
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 5
  - id: eval_3
    description: reconciles to silver; grain unique; no NULL measures; money stays DECIMAL
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

(none — additive: a new gold model + its `schema.yml` entry under `transform/models/gold`. `git checkout -- transform/models/gold` discards it; silver/bronze/raw and the other marts are untouched.)

---

## Observability Hooks

- **Expected duration:** gold mart build + schema tests, < 30s.
- **Key metric:** mart `gross_revenue` sum == silver non-cancelled order revenue.
- **Alert condition:** reconciliation mismatch; NULL measure; grain duplicate; a column consumed by B absent from `schema.yml`; a money column not DECIMAL.
- **Log tail:** `/tmp/gold_product_build.log`.

---

## Anti-Patterns

- **Don't read `raw.*` or `bronze.*` in this mart** — gold reads silver only via `ref('silver_orders')` / `ref('silver_products')`. Reading below silver skips typing + cleaning and lets the 14 injected defects into a money mart. Consume the clean conformed tables.
- **Don't recast money to FLOAT/DOUBLE** — `gross_revenue` and `gross_margin` are DECIMAL end-to-end (R4); a float cast silently loses cents. Carry `total_amount`/`cost` as NUMERIC and keep the aggregate DECIMAL.
- **Don't include `cancelled` orders in revenue/margin** — the mart is realized sales; cancelled orders inflate the numbers and break reconciliation to silver. Filter `status <> 'cancelled'`, consistent with `gold_revenue_by_category`.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (the verified brownfield)
- `transform/models/silver/**`, `transform/models/bronze/**` (upstream; consume via `ref()`)
- other marts' entries in `transform/models/gold/schema.yml` (append this mart's contract; don't rewrite siblings')

---

## Open Questions

1. **Margin definition** — is `gross_margin = gross_revenue − (silver_products.cost × quantity)` the agreed formula, or should discounts/landed cost factor in? Owner: VP Data. Buildable with the cost-based definition; refine if a richer cost model is frozen (spec §6, E4).
2. **Serving grain** — product×day confirmed, or does E4 want product×month / product-overall? Owner: VP Data. Mirrors `gold_revenue_by_category`'s category×day; change the date grain only if the frozen question set demands it.
