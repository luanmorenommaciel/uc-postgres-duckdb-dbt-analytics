# Reference · SQL Dialect Notes

> **Scope:** DuckDB SQL dialect cheatsheet for this warehouse — types (DECIMAL,
> TIMESTAMP WITH TIME ZONE), date/time functions, CAST, list/struct, information_schema,
> and the `pytz` materialization gotcha that bites the Python serving layer.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below traces to one of these. Verified against DuckDB stable docs, 2026-06-25.

- Data types overview: https://duckdb.org/docs/sql/data_types/overview
- Numeric / DECIMAL: https://duckdb.org/docs/sql/data_types/numeric
- Timestamp / TIMESTAMP WITH TIME ZONE: https://duckdb.org/docs/sql/data_types/timestamp
- Time zone support (ICU): https://duckdb.org/docs/stable/sql/data_types/timestamp#time-zone-support
- Date functions (`date_diff`, etc.): https://duckdb.org/docs/sql/functions/date
- CAST / type casting: https://duckdb.org/docs/sql/expressions/cast
- LIST type: https://duckdb.org/docs/sql/data_types/list
- STRUCT type: https://duckdb.org/docs/sql/data_types/struct
- `information_schema`: https://duckdb.org/docs/sql/meta/information_schema
- Python API: https://duckdb.org/docs/api/python/overview
- PostgreSQL extension type mapping: https://duckdb.org/docs/stable/core_extensions/postgres

## The `pytz` materialization gotcha (read this first)

DuckDB's Python client needs the optional `pytz` module to **materialize** a tz-aware
`TIMESTAMP WITH TIME ZONE` value into a Python object. Pulling one into Python without
`pytz` installed raises:

```
Required module 'pytz' failed to import
```

This is a *materialization-boundary* error, not a storage error — the column stores fine.
It fires only when a tz-aware timestamp crosses into Python via `.fetchone()`, `.fetchall()`,
`.df()`, `.arrow()`, etc. It WILL bite the FastAPI/MCP serving layer the first time a reader
returns a `TIMESTAMPTZ` column.

**Fix used in this repo:** cast tz timestamps to `VARCHAR` (or epoch) at the SQL boundary,
so the value crosses as text/number, never as a tz-aware object. The stored column stays
`TIMESTAMP WITH TIME ZONE` for downstream (dbt) consumers.

```sql
-- ingest.py L384: read the watermark back as text, never materialize the tz object
SELECT CAST(max(_source_watermark) AS VARCHAR) FROM raw.raw_orders;
-- or as epoch seconds:
SELECT epoch(max(_source_watermark)) FROM raw.raw_orders;
```

## Types — Postgres → DuckDB mapping (type fidelity)

The `postgres` extension infers these losslessly on `CREATE TABLE … AS SELECT FROM pg.…`.

| Postgres source | DuckDB landed | Fidelity rule |
|-----------------|---------------|---------------|
| `NUMERIC(p,s)` | `DECIMAL(p,s)` | Money is **never** cast to float/DOUBLE — exact base-10. |
| `TIMESTAMPTZ` | `TIMESTAMP WITH TIME ZONE` | tz-aware (UTC instant). Triggers the pytz gotcha on materialize. |
| `TIMESTAMP` | `TIMESTAMP` | Naive (no zone). Microsecond precision. |
| `INTEGER` / `BIGINT` | `INTEGER` / `BIGINT` | 1:1. |
| `TEXT` / `VARCHAR` | `VARCHAR` | 1:1 (no length enforcement in DuckDB). |
| `BOOLEAN` | `BOOLEAN` | 1:1. |

## DECIMAL

| Item | Note | Source |
|------|------|--------|
| Syntax | `DECIMAL(width, scale)`, alias `NUMERIC`. Default `DECIMAL(18,3)`. | data_types/numeric |
| Max precision | width up to 38 significant digits. | data_types/numeric |
| Storage | exact, base-10; arithmetic stays exact within precision. | data_types/numeric |
| Rule here | money columns (`unit_price`, `cost`, `amount`, `total_amount`) stay DECIMAL — never `::DOUBLE`. | — |

## TIMESTAMP WITH TIME ZONE

| Item | Note | Source |
|------|------|--------|
| Alias | `TIMESTAMPTZ`. Stored as a UTC instant (microsecond precision). | data_types/timestamp |
| Display / binning | needs the **ICU** extension to bin/arith by named zone; pre-bundled in the Python client. | timestamp#time-zone-support |
| Set session zone | `SET TimeZone = 'America/Los_Angeles';` (after `LOAD icu;` if not bundled). | timestamp#time-zone-support |
| `now()` caveat | `now()` returns `TIMESTAMPTZ`; binding `current_timestamp` in SQL to a plain `TIMESTAMP` column **strips the zone** to naive. Bind a `datetime.now(UTC)` from Python instead. | timestamp |
| Available zones | `SELECT * FROM pg_timezone_names();` | timestamp#time-zone-support |

## Date / time functions

| Function | Returns | Note | Source |
|----------|---------|------|--------|
| `date_diff(part, start, end)` | `BIGINT` | whole `part` boundaries crossed (e.g. `'day'`, `'hour'`). | functions/date |
| `date_sub(part, start, end)` | `BIGINT` | complete `part` intervals between (truncated). | functions/date |
| `date_part(part, ts)` / `extract(part FROM ts)` | `BIGINT`/`DOUBLE` | sub-field of a timestamp. | functions/date |
| `date_trunc(part, ts)` | timestamp | truncate to `part`. | functions/date |
| `epoch(ts)` | `DOUBLE` | seconds since 1970 — handy to dodge the pytz gotcha. | functions/date |
| `age(ts1, ts2)` | `INTERVAL` | calendar-aware difference. | functions/date |

```sql
-- whole days between two timestamps
SELECT date_diff('day', ordered_at, paid_at) AS days_to_pay FROM …;
```

## CAST

| Form | Note | Source |
|------|------|--------|
| `CAST(expr AS type)` | standard SQL cast; errors on invalid conversion. | expressions/cast |
| `expr::type` | shorthand (PostgreSQL-style). | expressions/cast |
| `TRY_CAST(expr AS type)` | returns `NULL` instead of erroring on bad input. | expressions/cast |
| `CAST(tstz AS VARCHAR)` | the repo's pytz-avoidance move at the Python boundary. | — |

## LIST and STRUCT (nested types)

| Type | Literal | Access | Source |
|------|---------|--------|--------|
| `LIST` / `type[]` | `[1, 2, 3]` | 1-based: `l[1]`; functions `list_value`, `unnest(l)`, `len(l)`. | data_types/list |
| `STRUCT` | `{'a': 1, 'b': 'x'}` | dot or bracket: `s.a` / `s['a']`; `struct_pack(a := 1)`. | data_types/struct |

`unnest()` expands a LIST into rows; nested types are first-class columns (no JSON needed).

## information_schema

Standard-SQL catalog views, plus DuckDB's own `duckdb_*` table functions.

| View / function | Use | Source |
|-----------------|-----|--------|
| `information_schema.tables` | list tables/views per schema. | meta/information_schema |
| `information_schema.columns` | column name / type / nullability / ordinal. | meta/information_schema |
| `DESCRIBE <table>` | quick column+type dump (DuckDB shorthand). | meta/information_schema |
| `duckdb_columns()` | richer column metadata (DuckDB-native). | meta/information_schema |

> Note: this repo resolves the orders schema-drift column on the **Postgres** side via
> `information_schema.columns` in psycopg (ingest.py L186) — DuckDB's own `information_schema`
> is the analogous view for the warehouse.

## Cross-references

- `quick-reference.md` — this tech's index
- `patterns/postgres-scan-ingest.md` — where the type mapping + pytz fix are applied
- `reference/performance-and-explain.md` — EXPLAIN / columnar-vectorized notes
