# Pattern · Route Design

> **Solves:** How to shape a read-only HTTP endpoint over `gold.*` so that one endpoint
> answers exactly one frozen analytical question, stays a thin adapter over the shared
> query core, and can never drift from its MCP-tool twin.
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- FastAPI — root docs: <https://fastapi.tiangolo.com/>
- FastAPI — query params + validation: <https://fastapi.tiangolo.com/tutorial/query-params/> and <https://fastapi.tiangolo.com/tutorial/query-params-str-validations/>
- FastAPI — response model: <https://fastapi.tiangolo.com/tutorial/response-model/>
- FastAPI — testing: <https://fastapi.tiangolo.com/tutorial/testing/>
- Verified against: FastAPI docs, 2026-06-25.
- Repo grounding: `sketch/fast-api-mcp.plan`, `tasks/T-20260625-api-fastapi.md`.

## Problem

Component B serves the frozen E4 question set. The temptation is to build a flexible,
parameter-rich query API ("give me any slice of the warehouse"). That is the wrong shape
here: it pulls JOINs and ad-hoc aggregation into the request path (breaks E2 — seconds,
not minutes) and tempts reads below gold (breaks E1 — isolation). The right shape is
**one endpoint per pre-aggregated gold mart**, each a thin adapter:

```text
HTTP request → validate query params → call B1 query-core fn → serialize → JSON
                                          │
                                          └── the SAME fn the MCP tool calls
```

The endpoint owns protocol framing (status codes, param validation, response schema). It
owns NO SQL — all SQL lives in `src/serving/queries.py` (B1), reused by both transports
so a tool and its endpoint can never return different answers.

## Pattern

`src/serving/queries.py` — the query core (one function per mart). Read-only, gold-only,
timestamps CAST to text at the SQL boundary so no tz-aware value reaches Python:

```python
# src/serving/queries.py
from __future__ import annotations
from src.warehouse import connect_read_only

def revenue_by_category(start: str | None = None, end: str | None = None) -> list[dict]:
    """Lookup over the pre-aggregated gold mart. No JOIN, no aggregate at request time."""
    sql = """
        SELECT category,
               CAST(day AS VARCHAR)     AS day,     -- tz-aware -> text at the SQL edge
               revenue,
               order_count
        FROM gold.gold_revenue_by_category
        WHERE (? IS NULL OR day >= ?)
          AND (? IS NULL OR day <  ?)
        ORDER BY day, category
    """
    conn = connect_read_only()            # never connect() / connect(read_only=False)
    try:
        cur = conn.execute(sql, [start, start, end, end])
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]
    finally:
        conn.close()
```

`src/serving/api.py` — the FastAPI transport. One endpoint per mart, each a thin adapter:

```python
# src/serving/api.py
from fastapi import FastAPI, Query
from pydantic import BaseModel
from src.serving import queries

app = FastAPI(title="gold serving", description="Read-only lookup over gold.* marts")

class RevenueRow(BaseModel):
    category: str
    day: str
    revenue: float
    order_count: int

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}            # liveness only — does NOT touch the warehouse

@app.get("/revenue/by-category", response_model=list[RevenueRow])
def revenue_by_category(
    start: str | None = Query(default=None, description="inclusive ISO date lower bound"),
    end:   str | None = Query(default=None, description="exclusive ISO date upper bound"),
):
    return queries.revenue_by_category(start=start, end=end)

@app.get("/freshness")
def freshness() -> dict:
    rows = queries.freshness()
    return rows[0] if rows else {}     # E3 instrument: exposes the gold freshness lag
```

Repeat the `@app.get(...) → queries.<fn>()` shape for `/customers/segments`,
`/orders/health`, `/payments/reconciliation`. Each is ~5 lines because the work is in B1.

## Why this shape

- **One question, one endpoint, one core fn.** The plan freezes the E4 question set; the
  route table mirrors the gold-mart table 1:1 (`sketch/fast-api-mcp.plan`). No generic
  query endpoint — flexibility belongs in dbt (Component A), not the serving edge.
- **Thin adapter, shared core.** Because the MCP tool calls the same `queries.*` function,
  "tool vs endpoint parity" is true by construction, not by a test that can rot. The test
  still exists, but it's confirming an invariant the architecture guarantees.
- **E2 by construction.** The endpoint does lookup + filter + serialize over a
  pre-aggregated mart. No JOIN below gold, no aggregate at request time — that is the
  mechanism behind "queries in seconds, not minutes."
- **E1 by construction.** Only `connect_read_only()` is reachable from serving; there is
  no write path and no reference to silver/bronze/raw/Postgres. A static isolation check
  proves it (grep the layer for `connect(` / `silver`/`bronze`/`raw`).
- **`/health` does not touch the warehouse.** Liveness must stay cheap and must not fail
  when gold is mid-publish; it returns a static payload.

## Anti-patterns

- **A generic `/query?sql=...` or richly-parameterized analytics endpoint.** Re-introduces
  request-time scans/JOINs (kills E2) and invites reads below gold (kills E1). Each
  question is its own frozen endpoint.
- **SQL in the endpoint.** If the `@app.get` handler contains a `SELECT`, the MCP tool and
  the endpoint can diverge. All SQL lives in `src/serving/queries.py`; endpoints call it.
- **A missing column handled by reaching into silver/gold internals.** A column not in the
  gold contract is a **new-mart request to Component A**, never a deeper read here. This
  is the one thing an agent must never get wrong (see `CLAUDE.md`).
- **Returning a tz-aware `datetime` straight from DuckDB.** It 500s at serialization
  because DuckDB needs `pytz` to materialize it. CAST to text/epoch in the SQL (B1), so
  the Pydantic field is a plain `str`/`int`. See `kb/duckdb/quick-reference.md`.
- **Opening a writable connection "just to be safe" / to `CREATE TEMP`.** Serving is
  strictly `connect_read_only()`. A write connection breaks E1-by-construction.
- **Background tasks / streaming responses.** Not used by this layer — endpoints return a
  finite gold lookup synchronously (see `patterns/background-tasks.md`,
  `patterns/sse-streaming.md`, both marked not-used).

## Verify

- **Route coverage** (mirrors `eval_2` in the task): every frozen question has a route.
  ```python
  from src.serving.api import app
  need = {"/health","/freshness","/revenue/by-category","/orders/health",
          "/payments/reconciliation","/customers/segments"}
  assert need <= {r.path for r in app.routes}
  ```
- **Endpoint returns gold + serializes tz-safe** (mirrors `eval_3`), via `TestClient`
  (<https://fastapi.tiangolo.com/tutorial/testing/>):
  ```python
  from fastapi.testclient import TestClient
  from src.serving.api import app
  import json
  r = TestClient(app).get("/freshness")
  assert r.status_code == 200
  json.dumps(r.json())          # must not raise on tz-aware timestamps
  ```
- **Isolation** (mirrors `eval_1`): the serving source uses `connect_read_only` and never
  `connect(read_only=False` / bare `connect()`, and references only `gold.*`.

## See also

- `quick-reference.md` — this tech's index
- `concepts/pydantic-boundaries.md` — typing the request/response edge
- `concepts/async-vs-sync.md` — `def` vs `async def` for a DuckDB-backed route
- `reference/response-models.md` — exact `response_model` serialization options
- `kb/duckdb/quick-reference.md` — the pytz / tz-aware CAST at the SQL boundary
