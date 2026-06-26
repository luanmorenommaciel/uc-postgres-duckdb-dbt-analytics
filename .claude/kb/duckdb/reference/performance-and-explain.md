# Reference · Performance and EXPLAIN

> **Scope:** Reading DuckDB query plans (`EXPLAIN` / `EXPLAIN ANALYZE`) and the
> columnar-vectorized execution model that makes the analytical store fast.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Verified against DuckDB stable docs, 2026-06-25.

- EXPLAIN (logical/physical plan): https://duckdb.org/docs/guides/meta/explain
- EXPLAIN ANALYZE (profiled run): https://duckdb.org/docs/guides/meta/explain_analyze
- Profiling statements: https://duckdb.org/docs/stable/sql/statements/profiling
- Why DuckDB is fast (vectorized engine): https://duckdb.org/why_duckdb
- Performance guide: https://duckdb.org/docs/guides/performance/overview
- Python API: https://duckdb.org/docs/api/python/overview

## EXPLAIN — see the plan without running it

`EXPLAIN <query>` prints the **physical** plan (operators, join order, estimated
cardinalities). It does not execute the query, so it is safe and instant.

```sql
EXPLAIN
SELECT c.country, count(*)
FROM raw.raw_orders o JOIN raw.raw_customers c USING (customer_id)
GROUP BY c.country;
```

Read it bottom-up: scans at the leaves, then filters/projections, then joins, then the
aggregate at the top. Each operator shows an **estimated** row count (`EC`). Use it to
confirm join order and that filter/projection pushdown happened.

## EXPLAIN ANALYZE — see the plan after running it

`EXPLAIN ANALYZE <query>` **executes** the query and annotates each operator with the
real, cumulative wall-clock time and the **actual** cardinality alongside the estimate.

```sql
EXPLAIN ANALYZE
SELECT date_diff('day', o.ordered_at, p.paid_at) AS lag, count(*)
FROM raw.raw_orders o JOIN raw.raw_payments p USING (order_id)
GROUP BY lag;
```

| Read | Meaning |
|------|---------|
| Total time at the top | end-to-end query wall-clock. |
| Per-operator time | cumulative time spent in that operator subtree. |
| Estimated vs actual cardinality | a large gap signals a stale/bad estimate → suspect join order or missing stats. |

> Caveat: because `EXPLAIN ANALYZE` actually runs the query, never run it on a mutating
> statement you don't want to execute. Readers should run it on a `connect_read_only()` handle.

## Reading plans against this repo's contract

- All readers route through `connect_read_only()` (`src/warehouse/connection.py`), so
  EXPLAIN/EXPLAIN ANALYZE in the serving layer run on a `READ_ONLY` handle and can run
  concurrently with the single writer.
- A `postgres`-attached scan (`pg.public.*`) shows a `POSTGRES_SCAN` operator in the plan —
  that work happens in Postgres at query time, not in DuckDB. The landing step copies into
  `raw.*` precisely to avoid re-reading the source on every analytical query.

## Columnar + vectorized execution model

| Property | What it means | Source |
|----------|---------------|--------|
| Columnar storage | values of one column stored contiguously; scans read only the columns a query touches. | why_duckdb |
| Vectorized execution | operators process batches (vectors, ~2048 values) per call, not row-at-a-time — amortizes per-tuple overhead, stays cache-friendly. | why_duckdb |
| Push-based pipelines | operators pull/push vectors through pipelines; enables parallelism across threads. | why_duckdb |
| Filter / projection pushdown | predicates and column pruning pushed toward scans (incl. into `postgres_scan`). | core_extensions/postgres |
| Multi-threaded by default | a single query parallelizes across cores; no per-query config needed. | guides/performance |

**Why it matters here:** the medallion (dbt) aggregations and the serving-layer queries
are wide scans + group-bys over `raw.*`/silver/gold — exactly the shape columnar+vectorized
execution is built for. Prefer narrow projections (select only needed columns) so the
columnar scan reads less; the planner handles the rest.

## Practical tips

- `SELECT` only the columns you need — columnar scans skip untouched columns entirely.
- Check the estimate-vs-actual gap in `EXPLAIN ANALYZE` before reaching for query rewrites.
- DuckDB parallelizes automatically; threads default to the core count. Don't hand-shard.
- Keep money as `DECIMAL` and timestamps as `TIMESTAMPTZ` — no perf reason to downcast, and
  downcasting money to DOUBLE loses exactness (see `reference/sql-dialect-notes.md`).

## Cross-references

- `quick-reference.md` — this tech's index
- `concepts/columnar-vectorized-model.md` — the execution model in depth
- `reference/sql-dialect-notes.md` — types and the pytz materialization boundary
