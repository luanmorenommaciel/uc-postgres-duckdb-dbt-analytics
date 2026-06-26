# CLAUDE.md — how agents work this repo

This repo builds a **dedicated analytical engine**: Postgres is the operational
source of record; a one-way feed lands it into an embedded DuckDB warehouse; a
**dbt medallion** (raw → bronze → silver → gold) refines it; a **read-only
FastAPI + MCP** layer serves the gold tables. The tech-spec is
[docs/tech-spec-analytical-engine.pdf](docs/tech-spec-analytical-engine.pdf); the
build plans are [sketch/duckdb-dbt-med-arch.plan](sketch/duckdb-dbt-med-arch.plan)
(Component A · Transform) and [sketch/fast-api-mcp.plan](sketch/fast-api-mcp.plan)
(Component B · Serve).

---

## The data flow (memorize this)

```
public.* (Postgres, containerized, mutable SOURCE OF RECORD + 14 silent defects)
   │   make land — ATTACH READ_ONLY, full refresh, defects land INTACT
   ▼
raw.*  (DuckDB embedded file)                ◄── GIVEN: built, verified, frozen
   │   dbt:  bronze (views, type) → silver (tables, clean+quarantine) → gold (marts)
   ▼
gold.* (DuckDB)                              ◄── THE SEAM (per-mart schema.yml contract)
   │   FastAPI endpoints  +  MCP tools  (read-only, one per frozen question)
   ▼
business user / agent                        ◄── TO BUILD (Component B)
```

What exists today: **everything up to `raw.*`** (the five `src/` packages — see
[src/README.md](src/README.md)). What we build: **the medallion and the serving
layer.** The task backlog is under [tasks/](tasks/).

---

## Three invariants no agent may break

### 1. One-way dependency: Postgres → DuckDB, never back

`src/transition` is the **only** crossing, and it `ATTACH`es Postgres
**`READ_ONLY`**, scoped to `SCHEMA 'public'`. The analytical store can never
write the source; the source never depends on the warehouse. The Postgres
password lives in a `TEMPORARY` DuckDB secret, never in the ATTACH string.

- **dbt** reads `raw.*` and writes `bronze/silver/gold.*` — it never touches Postgres.
- **Serving** reads `gold.*` read-only — it never touches Postgres, never writes the warehouse.
- `public.*` and `src/db/01_schema.sql` are the **frozen brownfield source** — do not
  modify them. Postgres is not a tech we build against; it is the given.

### 2. The raw.* → gold seam is a data contract

- `raw.*` lands **defects intact** — cleaning is **silver's** job, never the
  landing's, never bronze's.
- **Gold owns its contract**: each gold mart ships a per-mart `schema.yml`
  (columns, types, nullability, grain) that **Component A (dbt)** owns. The
  serving layer **binds to that contract** and reads **gold only** — never
  silver, bronze, raw, or Postgres. A column the serving layer needs that gold
  doesn't have is a **new-mart request to dbt**, never a deeper read.
- This is what makes the spec's **E1 (isolation)** true by construction.

### 3. "Eval passes = done" — the Task-Spec contract

Work is defined by the atomic Task-Specs in [tasks/](tasks/). Each carries a
runnable bash **Exit Check**. A task is **done when its evals pass — not when the
code "looks finished."** Do not hand-edit `signed_off`; the gate stamps it.

- Validate: `bash .claude/skills/task-spec/scripts/validate-task-spec.sh tasks/T-*.md`
- Gate + run evals: `bash .claude/skills/task-spec/scripts/safe-to-delegate.sh --stamp tasks/T-*.md`
- Build order (the `depends_on` DAG): **bronze → silver → {gold-marts, gold-freshness}
  → gold-atomic-publish → api-fastapi → mcp-tools**.

---

## How the agents are organized

Per tech, a **paired architect + developer** (in [.claude/agents/](.claude/agents/)),
each grounded in its KB under [.claude/kb/](.claude/kb/):

| Tech | Architect (plans, no Bash) | Developer (ships, has Bash) | KB |
|------|----------------------------|------------------------------|----|
| **dbt** | medallion layering, the gold `schema.yml` contract, dedup-signature + atomic-publish strategy | writes models, `schema.yml` tests, macros; turns evals green | `kb/dbt/` |
| **duckdb** | read-only/single-writer contract, `_gold_run_id` reads, type fidelity | connection helpers, analytical SQL, the `pytz` cast boundary | `kb/duckdb/` |
| **fastapi** | the read-only/gold-only boundary, B1 query-core / transport split | query core, endpoints, `TestClient` tests | `kb/fastapi/` |
| **mcp** | tool-vs-endpoint parity contract (thin — inherits the serving design) | the FastMCP server + tools over the shared core | `kb/mcp/` |

Three universal **closers** — `code-reviewer`, `code-simplifier`,
`code-documenter` — run pre-merge and ground in the tech KB matching the file's
language at runtime, plus `kb/code-quality/`.

**Architect plans, developer ships, closers polish.** Architects produce
trade-offs/manifests with no Bash; developers implement against the manifest and
do not re-litigate the design unless they hit a fatal constraint.

> Postgres, Airflow, and Spark have **no agents** here — by design. Postgres is the
> frozen source; the others aren't in this stack. Do not scaffold speculatively.

---

## Repo-wide conventions

- **Money & time are exact.** Money is `DECIMAL` (never cast to float);
  timestamps are tz-aware (`TIMESTAMP WITH TIME ZONE`). This fidelity must survive
  every layer.
- **The `pytz` trap.** DuckDB needs the `pytz` module to *materialize* a tz-aware
  timestamp into Python. Any Python consumer (the serving layer) must **CAST
  timestamps to VARCHAR/epoch at the SQL boundary** or it will raise at runtime.
  dbt models are SQL, so they're safe. See [.claude/kb/duckdb/quick-reference.md](.claude/kb/duckdb/quick-reference.md).
- **One warehouse connection contract.** Never open a raw `duckdb.connect()` or
  hardcode a `.duckdb` path. Route through `src/warehouse`: `connect()` (writers),
  `connect_read_only()` (readers). Path resolves from `DUCKDB_DATABASE`.
- **Freshness is land cadence, not streaming.** `_ingested_at` + the event
  watermark drive `gold_freshness.event_to_reportable_lag` (spec E3). We do **not**
  rebuild the verified full-refresh landing into CDC.
- **dbt runs after `make land`, serialized** (single-writer). Readers may run
  concurrently with the writer.
- **Make targets.** `make up` (Postgres), `make seed`, `make land`, and (to be
  wired) `make build` (land → dbt run → dbt test), `make serve` (FastAPI), MCP entrypoint.
