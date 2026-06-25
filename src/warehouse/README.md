# src/warehouse — the DuckDB warehouse substrate

The sole owner of the analytical store: one DuckDB file plus the connection
contract every component routes through. Nothing else in the repo hardcodes a
warehouse path or opens its own DuckDB connection.

DuckDB is an **embedded, in-process library** — a single local file, not a server
or container. Only Postgres is containerized.

## The single file

The warehouse is one DuckDB database file. By default it lives at
`src/warehouse/warehouse.duckdb` (gitignored). `paths.py` is the only place that
default literal exists.

## The `DUCKDB_DATABASE` contract

The warehouse location is configured **exclusively** via the `DUCKDB_DATABASE`
environment variable:

- **Only that name.** Legacy names `DUCKDB_PATH` and `WAREHOUSE_DB_PATH` are
  rejected: if either is set without `DUCKDB_DATABASE`, resolution raises so
  misconfiguration fails loud rather than silently writing to the wrong place.
- **Unset** → the default file `src/warehouse/warehouse.duckdb`.
- **A filesystem path** → resolved to its absolute form.
- **MotherDuck escape hatch** → a value starting with `md:` (or `motherduck:`) is
  honoured verbatim and never resolved to a filesystem path. `warehouse_path_str()`
  returns it as-is; `warehouse_path()` raises, since a DSN has no file path.

## Connecting

`connection.py` exposes the only sanctioned ways to open the warehouse:

- `connect(read_only=False)` — read/write. Writers (the `transition` landing step,
  dbt) use this. It ensures the parent directory exists before opening.
- `connect_read_only()` — read-only convenience (`access_mode=READ_ONLY`). Readers
  use this; a missing file surfaces as an error rather than a silently-created
  empty DB.
- `connection(...)` — a context-managed handle that always closes.

## Single-writer note

DuckDB is **single-writer-process**. Writers open `connect()` briefly and never
concurrently — serialized by the orchestration order (land, then transform).
Read-only readers may run concurrently with each other and with a single writer.
Keeping every connection behind these helpers is what makes that invariant
enforceable in one place.
