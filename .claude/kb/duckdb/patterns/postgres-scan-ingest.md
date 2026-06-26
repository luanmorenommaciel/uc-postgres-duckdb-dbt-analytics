# Pattern · Postgres Scan Ingest

> **Solves:** Land Postgres `public.*` into DuckDB `raw.*` one-way, with credentials
> kept out of SQL text and out of error output, and zero write-back risk to the source.
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- PostgreSQL extension (ATTACH / READ_ONLY / SCHEMA / SECRET): https://duckdb.org/docs/stable/core_extensions/postgres
- `CREATE SECRET` / secrets manager: https://duckdb.org/docs/configuration/secrets_manager
- Python API: https://duckdb.org/docs/api/python/overview
- Reference implementation in THIS repo: `src/transition/ingest.py`

## Problem

Postgres is the operational store; DuckDB is the analytical store. The contract is a
**one-way** dependency: `public.*` lands into `raw.raw_*` and DuckDB must *never* be
able to write Postgres. Two failure modes to design out:

1. A write path back into the source (a mutation, an accidental `INSERT INTO pg.…`).
2. A leaked password — the DuckDB docs warn that a connection error can print the
   full inline connection string (credentials included) to the terminal.

## Pattern

The repo uses a DuckDB-managed **temporary** secret plus a `READ_ONLY` ATTACH. The
password lives in the secret, never in the ATTACH string. See `src/transition/ingest.py`.

```python
# 1. Autoload is transparent, but install/load explicitly for determinism.
con.execute("INSTALL postgres")
con.execute("LOAD postgres")

# 2. Credentials go into a TEMPORARY secret (default). CREATE SECRET takes no bind
#    params, so env-derived option values are interpolated and single-quote-escaped
#    (value.replace("'", "''")). The password is never concatenated into ATTACH.
con.execute(
    "CREATE OR REPLACE SECRET pg_landing ("
    "  TYPE postgres,"
    "  HOST '...', PORT 5432, DATABASE '...', USER '...', PASSWORD '...'"
    ")"
)

# 3. Empty connection string => use everything from the secret. READ_ONLY is the
#    linchpin of the one-way dependency; SCHEMA 'public' narrows the attachment.
con.execute(
    "ATTACH '' AS pg (TYPE postgres, READ_ONLY, SECRET pg_landing, SCHEMA 'public')"
)

# 4. Land each entity 1:1. DuckDB infers NUMERIC(p,s) -> DECIMAL(p,s) and
#    TIMESTAMPTZ -> TIMESTAMP WITH TIME ZONE losslessly. Bind run-level values.
con.execute(
    "CREATE OR REPLACE TABLE raw.raw_customers AS "
    "SELECT customer_id, full_name, email, country, city, segment, created_at, "
    "       $ingested_at AS _ingested_at, "
    "       (SELECT max(created_at) FROM pg.public.customers) AS _source_watermark "
    "FROM pg.public.customers ORDER BY customer_id",
    {"ingested_at": ingested_at},  # one datetime.now(UTC) for the whole run
)

# 5. Always release the source + drop the secret, even on a mid-run error.
finally:
    con.execute("DETACH pg")
    con.execute("DROP SECRET IF EXISTS pg_landing")
```

The DuckDB connection itself is read/**write** (it writes `raw.*`); only the **ATTACH**
is `READ_ONLY`. It is opened through the connection contract: `connect(read_only=False)`
in `src/warehouse/connection.py` — the single place a DuckDB handle opens.

## Why this shape

- **Secret over inline DSN.** The docs explicitly warn that on a connection error the
  full inline string (with the password) can be printed. The temporary secret keeps the
  password out of the ATTACH literal *and* out of any error output.
- **TEMPORARY secret.** Default scope; nothing is persisted into the warehouse file, so
  the credential never survives the process.
- **`READ_ONLY` on ATTACH.** Per the docs, this prevents any modification to the
  underlying database — it is what makes the one-way dependency true *in code*, not just
  by convention.
- **`SCHEMA 'public'`.** Attaches only the one schema read, instead of every schema.
- **`CREATE OR REPLACE TABLE … AS SELECT`.** Full-refresh, idempotent re-runs. No
  incremental/MERGE state; the source watermark is computed per run and stamped on rows.
- **Bind `$ingested_at`, don't call `now()` in SQL.** `now()` in DuckDB SQL would strip
  the tz to a naive `TIMESTAMP`; binding a `datetime.now(UTC)` keeps it tz-aware and
  gives every row in the run the same freshness anchor.

## Anti-patterns

- **Password in the ATTACH string** — `ATTACH 'dbname=… password=…' AS pg (TYPE postgres)`.
  Leaks on connection error per the docs. Use a secret.
- **Omitting `READ_ONLY`** — the attachment becomes read/write and DuckDB *can* mutate
  Postgres. Breaks the one-way invariant.
- **Persistent secret** — `CREATE PERSISTENT SECRET` writes the credential to disk; the
  default temporary secret is correct here.
- **`now()` in the SELECT** — produces a naive `TIMESTAMP` and a per-row drift in the
  freshness anchor. Bind one UTC instant instead.
- **Materializing the tz watermark into Python** — `con.execute("SELECT max(_source_watermark) …").fetchone()`
  on a `TIMESTAMP WITH TIME ZONE` raises `Required module 'pytz' failed to import`. The
  repo reads it back as `CAST(... AS VARCHAR)` (ingest.py L384). See `reference/sql-dialect-notes.md`.
- **Identifiers as bind params** — no engine binds identifiers. The drifted orders column
  is resolved from `information_schema` (never user input) and templated into the text.

## Verify

- The ATTACH carries `READ_ONLY` and `SECRET pg_landing`; the ATTACH string is empty.
- Grep ingest.py: the password appears only inside `CREATE … SECRET`, never in `ATTACH`.
- `finally` runs `DETACH pg` + `DROP SECRET IF EXISTS pg_landing` on every path.
- Landed columns keep source types: `DESCRIBE raw.raw_payments` shows `amount DECIMAL(…)`
  (not DOUBLE) and `paid_at TIMESTAMP WITH TIME ZONE`.
- The run summary reads the watermark as VARCHAR — no `pytz` import is required.

## See also

- `quick-reference.md` — this tech's index
- `reference/sql-dialect-notes.md` — type fidelity + the pytz materialization gotcha
- `concepts/embedded-vs-warehouse.md` — why DuckDB is the in-process analytical store
