---
id: T-20260625-silver-conform
title: Silver dbt tables — conform entities, quarantine the 14 defects
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-bronze-views]
touches_paths:
  - transform/models/silver
source_note: sketch/duckdb-dbt-med-arch.plan
created: 1
tags: [dbt, silver, medallion, data-quality]
owner: (none)
priority: P1
severity: financial-critical
due_date: (none)
precondition: bronze views built (T-20260625-bronze-views signed off)
blocked_reason: (none)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# Silver dbt tables — conform entities, quarantine the 14 defects

> **Why:** Silver is the trust boundary. `raw.*`/bronze carry the 14 injected defects intact; silver is where they get neutralized so gold marts (and the money they report) are correct. Get the dedup key or the money invariant wrong here and every downstream metric is silently wrong — hence financial-critical.

---

## Goal

Ship conformed silver **tables** for the four entities plus `silver.quarantine_*`. Silver: (1) dedups `duplicate_order` by a **business signature** (`customer_id, product_id, quantity, unit_price, total_amount, ordered_at`), keeping the lowest `order_id` — NOT by `order_id`, because the injector re-inserts with a *new* `order_id`; (2) **quarantines, never deletes** rows failing rules (`negative_price`, `invalid_quantity`, zeroed `destructive_fix` totals, `malformed_data` status, out-of-vocab) with a reason code; (3) enforces the pinned vocab (`orders.status` ∈ placed/shipped/delivered/returned/cancelled — no `fulfilled`); (4) asserts `total_amount = quantity × unit_price`. Clean + quarantined must reconcile to the bronze row count (nothing vanishes).

---

## Context

- Defects are **silent by default** in the source (`_control` ledger only on `RECORD=1`), so correctness is proven by **invariant rules**, not by the ledger.
- The `duplicate_order` injector (`src/gen/failures.py`) re-inserts the latest order verbatim with a fresh PK → `unique(order_id)` would NOT catch it. Codex C2.
- Real `orders.status` vocab verified against `raw.*`: `placed, shipped, delivered, returned, cancelled`. There is no raw `fulfilled`. Codex C4.
- Silver materializes as **tables** (gold reads it repeatedly).
- Build order: bronze → **silver (this)** → gold → API → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: silver builds and all silver dbt schema/data tests pass
eval_1() {
  cd transform || return 1
  uv run dbt build --select "silver" --quiet >/tmp/silver_build.log 2>&1 || return 1
  grep -Eq "Completed successfully|PASS" /tmp/silver_build.log
}

# eval-2: money + vocab invariants hold in clean silver_orders (no defects leaked through)
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
bad_money = con.execute("""
  SELECT count(*) FROM silver.silver_orders
  WHERE total_amount <> quantity*unit_price OR unit_price < 0 OR quantity <= 0
""").fetchone()[0]
assert bad_money == 0, f"{bad_money} money-invariant violations leaked into silver_orders"
ALLOWED = {'placed','shipped','delivered','returned','cancelled'}
got = {r[0] for r in con.execute("SELECT DISTINCT status FROM silver.silver_orders").fetchall()}
assert got <= ALLOWED, f"out-of-vocab status in silver_orders: {got - ALLOWED}"
con.close()
PY
}

# eval-3: duplicate_order dedup works on business signature, and quarantine reconciles (nothing vanishes)
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.warehouse.connection import connect_read_only
con = connect_read_only()
dupes = con.execute("""
  SELECT count(*) FROM (
    SELECT customer_id, product_id, quantity, unit_price, total_amount, ordered_at, count(*) c
    FROM silver.silver_orders
    GROUP BY 1,2,3,4,5,6 HAVING count(*) > 1
  )
""").fetchone()[0]
assert dupes == 0, f"{dupes} duplicate business-signatures survived dedup"
b = con.execute("SELECT count(*) FROM bronze.bronze_orders").fetchone()[0]
c = con.execute("SELECT count(*) FROM silver.silver_orders").fetchone()[0]
q = con.execute("SELECT count(*) FROM silver.quarantine_orders").fetchone()[0]
assert c + q == b, f"reconciliation broken: clean {c} + quarantined {q} != bronze {b}"
con.close()
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: silver builds; all silver dbt tests pass
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 45
  - id: eval_2
    description: money invariant + pinned status vocab hold in clean silver_orders
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: business-signature dedup works; quarantine reconciles to bronze count
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
  output_artifacts: [transform/models/silver]
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

(none — additive: new silver models + tests under `transform/models/silver`. `git checkout -- transform/models/silver` discards it; bronze and raw are untouched.)

---

## Observability Hooks

- **Expected duration:** silver build + tests, < 60s.
- **Key metric:** quarantine reconciliation (clean + quarantined == bronze count) per entity.
- **Alert condition:** any money-invariant or out-of-vocab row in a clean silver table; reconciliation mismatch.
- **Log tail:** `/tmp/silver_build.log`.

---

## Anti-Patterns

- **Don't dedup `duplicate_order` by `order_id`** — the injector re-inserts with a new PK, so PK uniqueness still passes while the dup survives and overcounts revenue. Key on the business signature.
- **Don't hard-delete failing rows** — quarantine with a reason code so the pipeline is auditable and reconciles to bronze. Silent drops read as "clean" when they aren't.
- **Don't invent a `fulfilled` status** — it is not in the raw vocab. Any "fulfilled" concept is a gold-layer derived mapping, not a silver status value.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/**` (brownfield; especially `src/gen/failures.py` — the defect model is the fixture, not a thing to change)
- `transform/models/bronze/**` (upstream layer; consume via `ref()`)

---

## Open Questions

1. **Quarantine vs. drop policy** — default is quarantine (auditable). Confirm the demo doesn't want hard drops. Owner: us (default chosen); does not block build.
