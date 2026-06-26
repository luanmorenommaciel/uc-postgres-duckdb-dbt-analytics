# FastAPI — Quick Reference

> **Purpose:** Fast lookup for FastAPI. The first read for both the
> architect and developer agents, and for any closer working a file in this tech.
> **Hard limit:** 100 lines. Deep material lives in `concepts/`, `patterns/`, `reference/`.

## Identity

FastAPI is the **Component B · Serve** transport in this repo: a thin, **read-only,
gold-only** HTTP surface over the DuckDB `gold.*` marts. One endpoint answers one
frozen analytical question (`/revenue/by-category`, `/customers/segments`,
`/orders/health`, `/payments/reconciliation`, `/freshness`) plus `/health`. Every
endpoint is a thin adapter over a shared **B1 query core** (`src/serving/queries.py`):
validate params → call the core → serialize. The same core backs the MCP tools, so
a tool and its endpoint can never disagree. **The one thing an agent must never get
wrong:** serving reads `gold.*` ONLY, via `connect_read_only()` — it NEVER writes the
warehouse and NEVER reads silver/bronze/raw/Postgres. A missing column is a new-mart
request to Component A (dbt), never a deeper read. This makes spec E1 (isolation) true
by construction, and E2 (seconds, not minutes) true because lookups hit pre-aggregated
gold with no scan or JOIN below gold at request time. Source: <https://fastapi.tiangolo.com/>.

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  FastAPI — AGENT FLOW                         │
├─────────────────────────────────────────────────────────────┤
│  1. CLASSIFY → architect (plan) or developer (ship)?        │
│  2. LOAD     → this KB, then the matching concept/pattern    │
│  3. VALIDATE → KB + MCP agreement matrix                     │
│  4. ACT      → cite the specific doc per decision/finding    │
│  5. VERIFY   → tests/assertions green; grounded in docs      │
└─────────────────────────────────────────────────────────────┘
```

## Index

| Kind | Doc | Read it when |
|------|-----|--------------|
| concept | `concepts/pydantic-boundaries.md` | typing the request/response edge of an endpoint |
| concept | `concepts/async-vs-sync.md` | choosing `def` vs `async def` for a DuckDB-backed route |
| concept | `concepts/dependency-injection.md` | sharing the read-only connection / params across routes |
| pattern | `patterns/route-design.md` | adding/shaping a one-question read-only endpoint |
| pattern | `patterns/background-tasks.md` | NOT USED — read-only serving has no deferred work |
| pattern | `patterns/sse-streaming.md` | NOT USED — endpoints return finite gold lookups, not streams |
| reference | `reference/response-models.md` | exact `response_model` / Pydantic v2 serialization options |

## Cross-references

| Need | Where |
|------|-------|
| Project conventions every task follows | `CLAUDE.md` at repo root |
| tz-aware timestamp / `pytz` gotcha at the SQL boundary | `kb/duckdb/quick-reference.md` |
| Read-only connection contract (`connect_read_only`) | `src/warehouse/connection.py` |
| The serving plan this layer implements | `sketch/fast-api-mcp.plan`, `tasks/T-20260625-api-fastapi.md` |
| Cross-tech code-quality universals | `kb/code-quality/quick-reference.md` |
