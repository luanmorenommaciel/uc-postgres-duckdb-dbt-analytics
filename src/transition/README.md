# src/transition — Postgres → DuckDB landing

The data-movement step. `transition` reads the operational Postgres source and
lands it into the DuckDB warehouse as `raw.raw_*` tables. It is the one place the
source crosses into the analytical store.

## What it does

For each of the four source entities — `customers`, `products`, `orders`,
`payments` — `transition`:

1. **Resolves schema drift once** (orders only). A short read-only psycopg probe
   reads `information_schema` to decide whether the order→customer link column is
   `customer_id` or the drifted `user_id`. The resolved column is templated into
   the orders projection (aliased back to `customer_id`) and drives the bound
   `_schema_drift` flag, so the identifier and the flag can never disagree.
2. **ATTACHes Postgres READ-ONLY** through DuckDB's `postgres` extension, using a
   DuckDB-managed temporary secret so the password never enters the `ATTACH`
   string or any error output. The source is never modified.
3. **Copies each entity** with `CREATE OR REPLACE TABLE raw.raw_<entity> AS
   SELECT ...`, preserving source types 1:1 (`NUMERIC` → `DECIMAL`, `TIMESTAMPTZ`
   → `TIMESTAMP WITH TIME ZONE`). Money stays `DECIMAL`; timestamps stay tz-aware.
4. **DETACHes and drops the secret** in a `finally`, so a mid-run error still
   cleans up.

Defects are **never** dropped or repaired here — they land intact in `raw.*`. The
warehouse target is the embedded DuckDB file owned by [`src/warehouse`](../warehouse/README.md);
DuckDB is an in-process library, not a server or container.

## The three stamp columns

Every landed row carries run-level lineage columns appended after the source
columns:

| Column              | Meaning |
|---------------------|---------|
| `_ingested_at`      | One tz-aware UTC instant (`datetime.now(UTC)`) shared by every row of every table in the run — the freshness anchor. Bound as a parameter, never `now()` in SQL (which would strip the timezone). |
| `_source_watermark` | The run's high-watermark `max(<watermark_col>)` from the source, identical on every row, `NULL` on an empty source. |
| `_schema_drift`     | **orders only.** `TRUE` when the source link column drifted to `user_id`. The other three tables do not carry this column (the source DDL asymmetry is preserved). |

## Schema-drift handling

The orders source column can rename from `customer_id` to `user_id` (the
`schema_drift` defect). `transition` resolves the live column from
`information_schema` before any `ATTACH`, selects it `AS customer_id` into the
stable raw slot, and records the fact in `_schema_drift`. Downstream consumers
always see a `customer_id` column plus a boolean telling them whether a rename
occurred.

## Full refresh

Landing is a **full refresh**, not incremental: no watermark state, no
`MERGE`/`ON CONFLICT`, no lookback window. `CREATE OR REPLACE TABLE` makes re-runs
idempotent (apart from `_ingested_at`, which advances by design). A failure mid-run
leaves already-landed tables intact and propagates loudly.

## How to run it

```bash
make land
# or directly:
uv run python -m src.transition.cli land
```

Run it after `make up` (Postgres healthy) and `make seed` (a baseline to land).
Override the warehouse target with `DUCKDB_DATABASE`; the default is
`src/warehouse/warehouse.duckdb`.
