# DuckDB — Quick Reference

> **Purpose:** Fast lookup for DuckDB. The first read for both the
> architect and developer agents, and for any closer working a file in this tech.
> **Hard limit:** 100 lines. Deep material lives in `concepts/`, `patterns/`, `reference/`.

## Identity

DuckDB is an **embedded, in-process** analytical (OLAP) database — a single local file
loaded as a library, **not** a server or container. There is no DuckDB service to start;
only Postgres is containerized. Here DuckDB is the **analytical store**: Postgres `public.*`
lands **one-way** into DuckDB `raw.*`, then dbt builds the medallion and FastAPI/MCP serve it.
Two things an agent must never get wrong: (1) the Postgres ATTACH is `READ_ONLY` with the
password in a **temporary SECRET**, never in the ATTACH string — DuckDB can never write
Postgres; (2) materializing a `TIMESTAMP WITH TIME ZONE` into Python without `pytz` raises
`Required module 'pytz' failed to import` — cast tz timestamps to `VARCHAR`/epoch at the SQL
boundary. Docs: https://duckdb.org/docs/

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  DuckDB — AGENT FLOW                         │
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
| concept | `concepts/embedded-vs-warehouse.md` | "is this a server?" — embedded vs warehouse model |
| concept | `concepts/columnar-vectorized-model.md` | reasoning about why analytical scans are fast |
| concept | `concepts/motherduck-cloud-path.md` | the `md:` cloud escape hatch (`DUCKDB_DATABASE`) |
| pattern | `patterns/postgres-scan-ingest.md` | landing Postgres → `raw.*` (READ_ONLY ATTACH + SECRET) |
| pattern | `patterns/gold-obt-query.md` | building the gold one-big-table query |
| pattern | `patterns/anomaly-profiling-queries.md` | profiling defects/anomalies in the data |
| reference | `reference/sql-dialect-notes.md` | exact types, `date_diff`, CAST, the **pytz** gotcha |
| reference | `reference/performance-and-explain.md` | reading `EXPLAIN` / `EXPLAIN ANALYZE` plans |

## Cross-references

| Need | Where |
|------|-------|
| Project conventions every task follows | `AGENTS.md` at repo root |
| Cross-tech code-quality universals | `kb/code-quality/quick-reference.md` |
| Architecture plans this tech serves | `sketch/duckdb-dbt-med-arch.plan`, `sketch/fast-api-mcp.plan` |
| The ONE place a DuckDB connection opens | `src/warehouse/connection.py` — `connect()` (writers), `connect_read_only()` (readers) |
| The Postgres → `raw.*` landing reference impl | `src/transition/ingest.py` |
