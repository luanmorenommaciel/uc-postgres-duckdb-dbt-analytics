# Rules — repo invariants (enforced for every agent)

These are hard rules, not preferences. They derive from the tech-spec and the
verified brownfield. The closers (`code-reviewer`) flag violations as BLOCKER.
Full context: [CLAUDE.md](../../CLAUDE.md).

## R1 · One-way dependency (Postgres → DuckDB)

- **MUST NOT** write to Postgres `public.*` from any analytical code. The only
  crossing is `src/transition`, which ATTACHes `READ_ONLY`.
- **MUST NOT** modify the frozen source: `src/db/01_schema.sql`,
  `docker-compose.yml`, or anything under `src/db/`, `src/seed/`, `src/gen/`,
  `src/transition/`, `src/warehouse/` (the verified brownfield).
- **MUST NOT** scaffold a Postgres/Airflow/Spark agent. Postgres is the given
  source; the rest aren't in this stack.

## R2 · The raw.* → gold seam

- **Cleaning is silver's job.** Bronze is lossless typing; `raw.*` carries defects
  intact. **MUST NOT** drop/repair rows in bronze.
- **Gold owns the contract.** Every gold mart **MUST** ship a per-mart
  `schema.yml` (columns, types, grain). The serving layer **MUST** read `gold.*`
  only and bind to that contract — **MUST NOT** read silver/bronze/raw/Postgres or
  issue a JOIN/aggregate below gold.
- A needed-but-absent gold column is a **new-mart request to dbt**, never a deeper read.

## R3 · Connection contract

- **MUST** route every DuckDB connection through `src/warehouse`:
  `connect()` (writers), `connect_read_only()` (readers). **MUST NOT** call
  `duckdb.connect()` directly or hardcode a `.duckdb` path.
- Serving **MUST** use `connect_read_only()` — no writable connection in the
  serving layer (this is E1-by-construction).
- dbt runs **after** `make land`, serialized (single-writer).

## R4 · Money, time, and the pytz trap

- Money is `DECIMAL` end-to-end — **MUST NOT** cast to float/double.
- Timestamps are tz-aware — **MUST** preserve `TIMESTAMP WITH TIME ZONE`.
- Any Python consumer of a tz-aware timestamp **MUST** `CAST` it to VARCHAR/epoch
  at the SQL boundary (DuckDB's `pytz`-on-materialize trap). dbt SQL is exempt.

## R5 · Correctness constraints (from the adversarial review)

- `duplicate_order` dedup **MUST** key on a **business signature**, never
  `order_id` (the injector re-inserts with a new PK).
- `gold_freshness` **MUST** carry `event_to_reportable_lag` (event watermark vs
  `_ingested_at`) — not landing recency alone.
- Order status vocab is `placed/shipped/delivered/returned/cancelled` — there is
  **no raw `fulfilled` status**; any "fulfilled" rate is a derived gold mapping.
- Gold **MUST** publish atomically: all marts share one `_gold_run_id`; readers
  bind to the latest fully-published generation.

## R6 · Eval passes = done

- A task is done **only** when its Task-Spec Exit Check passes. **MUST NOT**
  hand-edit `signed_off` — the gate stamps it.
- Architects produce manifests (no Bash); developers implement against them and
  do not re-open settled design without a fatal constraint.
