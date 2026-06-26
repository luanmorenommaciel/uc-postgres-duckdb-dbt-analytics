---
id: T-20260625-api-fastapi
title: FastAPI read-only serving — query core + one endpoint per gold mart
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-gold-marts, T-20260625-gold-freshness, T-20260625-gold-atomic-publish]
touches_paths:
  - src/serving
source_note: sketch/fast-api-mcp.plan
created: 5
tags: [fastapi, serving, read-only, E4, E2]
owner: (none)
priority: P1
severity: feature
due_date: (none)
precondition: gold marts + freshness built and atomically published; E4 set frozen
blocked_reason: final endpoint list gated on the frozen E4 question set (VP Data, spec §6)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# FastAPI read-only serving — query core + one endpoint per gold mart

> **Why:** This is half of the self-serve surface (spec E4) and the place E2's "seconds, not minutes" is realized — lookups over pre-aggregated gold. It must be strictly read-only over gold (E1 by construction) and must never reach below gold; if it does, the isolation guarantee and the contract seam both break.

---

## Goal

Ship a **B1 query-core** module (`src/serving/queries.py`): one read-only function per gold mart, each opening the warehouse via `connect_read_only()`, casting tz-aware timestamps at the SQL boundary (the `pytz` guard), reading the latest fully-published `_gold_run_id` generation, and returning typed rows. Then a **FastAPI app** (`src/serving/api.py`) with one thin endpoint per mart (`/revenue/by-category`, `/customers/segments`, `/orders/health`, `/payments/reconciliation`, `/freshness`) plus `/health`. Endpoints validate params and serialize the core's output — no JOINs below gold, no ad-hoc aggregates. `make serve` launches it.

---

## Context

- Input contract: the gold `schema.yml` owned by Component A (`gold-marts`, `gold-freshness`). B binds to it; a column not in that contract is a new-mart request to A, never a deeper read. Codex C3.
- Reads the latest complete `_gold_run_id` generation so concurrent dbt runs never expose a mixed set. Codex C5.
- `pytz` guard is mandatory: DuckDB needs `pytz` to materialize tz-aware timestamps into Python — cast to text/epoch in SQL. (Proven during brownfield verification.)
- `/freshness` exposes `gold_freshness.event_to_reportable_lag` — the E3 instrument, not a business question.
- Final endpoint list is gated on the frozen E4 set; the five here are the candidate surface.
- Build order: bronze → silver → gold → **API (this)** → MCP.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: the query core imports and opens the warehouse READ-ONLY (no write path)
eval_1() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
import inspect, src.serving.queries as q
src = inspect.getsource(q)
assert "connect_read_only" in src, "query core must use connect_read_only()"
assert "connect(read_only=False" not in src and "connect()" not in src, "query core must not open a writable connection"
# at least one query function callable
fns = [f for f in dir(q) if f.startswith(("get_","query_","revenue","orders","payments","customers","freshness"))]
assert fns, "no query-core functions found"
PY
}

# eval-2: the FastAPI app exposes the expected routes (one per gold mart + health/freshness)
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from src.serving.api import app
paths = {r.path for r in app.routes}
need = {"/health","/freshness","/revenue/by-category","/orders/health","/payments/reconciliation","/customers/segments"}
missing = need - paths
assert not missing, f"missing routes: {missing}"
PY
}

# eval-3: an endpoint returns gold data with tz timestamps serialized (no pytz crash), read-only honored
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
from fastapi.testclient import TestClient
from src.serving.api import app
c = TestClient(app)
r = c.get("/freshness")
assert r.status_code == 200, f"/freshness -> {r.status_code}"
body = r.json()
assert body, "/freshness returned empty"
# serialization must not raise on tz-aware timestamps (the pytz trap)
import json; json.dumps(body)
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: query core is read-only (connect_read_only, no write path)
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_2
    description: FastAPI app exposes one route per gold mart + health/freshness
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: an endpoint returns gold data, tz timestamps serialize without pytz crash
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 15

retry_policy:
  max_iterations: 15
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  version: 2
  read: [intent, contract, guardrails, operations]
  produce:
    - code
    - tests
    - config
  required_tools: [git, bash]
  timeout_minutes: 30
  sandbox_type: host
  output_artifacts: [src/serving/queries.py, src/serving/api.py]
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

(none — additive: a new `src/serving/` package + a `make serve` target. `git checkout -- src/serving Makefile` discards it; the warehouse and transform are untouched.)

---

## Observability Hooks

- **Expected duration:** endpoint p95 sub-second (lookup over pre-aggregated gold) — the E2 mechanism.
- **Key metric:** endpoint latency p95/p99; `/freshness` lag value.
- **Alert condition:** any write connection opened by serving; a 500 from a tz-serialization (pytz) error; endpoint reading below gold.
- **Log tail:** uvicorn stdout.

---

## Anti-Patterns

- **Don't open a writable warehouse connection** — serving is strictly `connect_read_only()`; a write path breaks E1-by-construction.
- **Don't query silver/bronze/raw/Postgres** — read gold only; a missing column is a new mart request to Component A, not a deeper read.
- **Don't return tz-aware timestamps unmarshalled** — cast in SQL; DuckDB's pytz-on-materialize trap will 500 the endpoint otherwise.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/db/**`, `src/transition/**`, `src/warehouse/**` (read via `connect_read_only`; do not alter the warehouse contract)
- `transform/**` (the gold contract is consumed, not edited, by serving)

---

## Open Questions

1. **Frozen E4 question set** — fixes the final endpoint list. Owner: VP Data (spec §6). Candidate endpoints buildable; final surface gated.
2. **`_gold_run_id` read strategy** — confirm "latest fully-published id" selection against A's publish mechanism (`gold-atomic-publish`). Resolve during build.
