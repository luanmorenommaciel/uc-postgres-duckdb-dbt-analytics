# dbt — Quick Reference

> **Purpose:** Fast lookup for dbt. The first read for both the
> architect and developer agents, and for any closer working a file in this tech.
> **Hard limit:** 100 lines. Deep material lives in `concepts/`, `patterns/`, `reference/`.

## Identity

dbt is a SQL-first transformation framework: you write `SELECT` models, dbt builds the
dependency graph from `ref()`/`source()` and materializes them in order
([docs.getdbt.com](https://docs.getdbt.com/)). In THIS repo it is **Component A**, the
medallion built *on top of* the frozen `raw.*` tables that `make land` one-way replicates
from Postgres into DuckDB. The adapter is **dbt-duckdb** ([github.com/duckdb/dbt-duckdb](https://github.com/duckdb/dbt-duckdb));
the warehouse file resolves from `DUCKDB_DATABASE` via `src/warehouse`, and dbt runs
serialized (single-writer) only **after** `make land`. Layers: bronze (views, lossless
typing) → silver (tables, conform + quarantine the 14 injected defects) → gold (tables,
marts + per-mart `schema.yml`). The one thing an agent must never get wrong: **dbt reads
`raw.*` and never writes back to Postgres; cleaning is silver's job (raw lands defects
intact); the gold `schema.yml` is the contract Component B (FastAPI/MCP) compiles against.**

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  dbt — AGENT FLOW                         │
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
| reference | `reference/dbt-yaml-schema.md` | Writing `dbt_project.yml`, `sources.yml`, or a gold `schema.yml` contract |
| reference | `reference/jinja-helpers.md` | Need exact `ref()` / `source()` / `config()` signatures |
| pattern | `patterns/ref-graph-discipline.md` | Wiring bronze→silver→gold so each layer only reads the one below |
| pattern | `patterns/incremental-models.md` | Considering incremental builds (cited-TODO stub) |
| pattern | `patterns/ci-build-and-state-defer.md` | Slim CI / state:modified deferral (cited-TODO stub) |
| concept | `concepts/models-and-materializations.md` | Choosing view vs table per layer (cited-TODO stub) |
| concept | `concepts/tests-and-sources.md` | Declaring sources + schema/data tests (cited-TODO stub) |
| concept | `concepts/snapshots-mental-model.md` | SCD2 / snapshot semantics (cited-TODO stub) |

## Cross-references

| Need | Where |
|------|-------|
| Project conventions every task follows | `CLAUDE.md` at repo root |
| Cross-tech code-quality universals | `kb/code-quality/quick-reference.md` |
| Architecture plans this tech serves | `sketch/duckdb-dbt-med-arch.plan`, `sketch/fast-api-mcp.plan` |
| The atomic task specs dbt implements | `tasks/T-20260625-{bronze-views,silver-conform,gold-marts,gold-freshness,gold-atomic-publish}.md` |
| Warehouse-path / connection rule | `src/warehouse` (resolves `DUCKDB_DATABASE`) |
| The contract seam B binds to | `transform/models/gold/schema.yml` (owned by A) |
