# src/ — the brownfield base

`src/` is the deterministic foundation the rest of the workshop is built on: a
synthetic generator feeds **PostgreSQL**, and a transition step lands that source
into **DuckDB** via `ATTACH`. The flow is one-directional — Postgres is the
operational source, DuckDB is the analytical store, and nothing flows back.

DuckDB is an **embedded, in-process library** — a single local file, not a server
or container. Only Postgres is containerized. There is no DuckDB service to start.

```
                  generate / seed            make land
  synthetic data ───────────────▶ PostgreSQL ──ATTACH/copy──▶ DuckDB (raw.*)
                                   (container)                  (embedded file)
```

> **Verified end-to-end.** On a clean slate, the full pipeline runs and the row
> counts reconcile (see [Verified end-to-end](#verified-end-to-end) below):
> `make seed` loads Postgres (customers=500, products=200, orders=5000,
> payments=5000); `make land` produces `raw.*` with exact row parity. The
> `_control` ledger is never landed — the warehouse holds only the `raw` schema.

---

## The five packages

| Package          | Role                                                              | Key entry points |
|------------------|-------------------------------------------------------------------|------------------|
| `src/db`         | Postgres source contract + write helpers; owns the DDL.           | `connect()`, `insert_returning_ids()`, `count()`, `truncate_all()`, `db/01_schema.sql` |
| `src/seed`       | Deterministic clean baseline (correlated synthetic data).         | `python -m src.seed.seed`, `seed.run()`, `EcommerceFactory` |
| `src/gen`        | Chaos generator: normal traffic + 14 defect injectors.           | `python -m src.gen.cli`, `engine.run_traffic/inject/watch`, `failures.REGISTRY` |
| `src/transition` | Postgres → DuckDB `raw.*` landing (full refresh).                 | `python -m src.transition.cli land`, `ingest.land_all()`, `ingest.land_entity()` |
| `src/warehouse`  | DuckDB substrate: the single file + the connection contract.     | `warehouse_path_str()`, `connect()`, `connect_read_only()`, `connection()` |

`db` and `warehouse` are the two leaves; `transition` is the only bridge between
the Postgres and DuckDB halves.

### `src/db`

The Postgres source contract and the write helpers everything else routes through.
`db/01_schema.sql` is the DDL (mounted into the container and auto-applied on first
boot). Public entry points: `conninfo()`, `connect()`, `insert_returning_ids()`,
`count()`, `truncate_all()`.

**Edges.** A leaf — it depends on nothing else in `src/`. It is imported by `seed`,
by `gen/repository`, and by `transition/ingest`.

### `src/seed`

The deterministic clean baseline. The CLI builds correlated rows and loads them in
a single committed transaction:

```bash
python -m src.seed.seed --customers 500 --products 200 --orders 5000 --seed 42 --truncate
```

Public entry points: the CLI, `seed.run()`, and `EcommerceFactory` with
`.customer()` / `.product()` / `.order()` / `.payment()` plus its frozen value
objects. The data is **correlated, not random**: orders never predate the
customer's signup; product cost is 45–80% of `unit_price`; a returned order yields
a refunded payment; the payment amount mirrors the order total. Vocabulary is fixed
(8 `CATEGORIES`, plus `SEGMENTS`, `ORDER_STATUSES`, `PAYMENT_METHODS`,
`PAYMENT_STATUSES`).

**Edges.** Imports `src.db.connection`. Its `EcommerceFactory` is reused by
`gen/engine` so generated traffic is shaped like the seed.

### `src/gen`

The chaos generator — normal traffic plus 14 defect injectors. It knows *what* it
corrupts and nothing about *who* consumes it.

```bash
python -m src.gen.cli list                 # show the 14 failure modes
python -m src.gen.cli traffic --orders 200 # insert normal orders
python -m src.gen.cli inject <failure>     # inject one defect (silent)
python -m src.gen.cli reset-schema         # revert schema drift
python -m src.gen.cli watch                # stream traffic + random failures
```

Public surface: the CLI, `engine.run_traffic` / `inject` / `watch`,
`TrafficGenerator`, `failures.REGISTRY` / `get` / `InjectionResult` / `Failure`,
and the `repository.*` helpers.

**Edges.** `gen/repository` imports `src.db.connection`; `gen/engine` imports
`src.seed.factories`. See [The generator & failures](#the-generator--failures).

### `src/transition`

The data-movement step. `transition` reads the operational Postgres source and
lands it into the DuckDB warehouse as `raw.raw_*` tables. It is the one place the
source crosses into the analytical store.

```bash
python -m src.transition.cli land
```

Public surface: the CLI, `ingest.land_all(con=None)`, `ingest.land_entity(...)`,
the re-exported `EntitySpec` / `LandResult`, and `RAW_SCHEMA = "raw"`.

**Edges.** Imports `src.db.connection.conninfo` (source) and
`src.warehouse.connection.connect` (target). It deliberately does **not** import
`src.gen` — it copies `order_customer_column` verbatim to keep its dependencies to
`db` + `warehouse` only. See [The DuckDB landing contract](#the-duckdb-landing-contract).

### `src/warehouse`

The sole owner of the analytical store: one DuckDB file plus the connection contract
every component routes through. Nothing else in the repo hardcodes a warehouse path
or opens its own DuckDB connection.

Public surface: `paths.warehouse_path_str()` / `warehouse_path()`, and
`connection.connect()` / `connect_read_only()` / `connection()`.

**Edges.** A leaf — no `src/` imports. Consumed by `transition/ingest`. See
[The warehouse contract](#the-warehouse-contract).

### Dependency graph

```
src.seed.seed ──→ src.db.connection
src.seed.factories  (no internal deps)

src.gen.cli ──→ src.gen.engine ──→ src.gen.repository ──→ src.db.connection
                        └────────→ src.seed.factories
src.gen.failures ──→ src.gen.repository

src.transition.cli ──→ src.transition.ingest ──→ src.db.connection (conninfo)
                                               └─→ src.warehouse.connection (connect)

src.warehouse.connection ──→ src.warehouse.paths   (leaf)
```

`db` and `warehouse` are the two leaves; `transition` is the only bridge between
the Postgres and DuckDB halves.

---

## End-to-end data flow

```bash
make up                                  # Postgres boots; 01_schema.sql auto-applied
make seed                                # deterministic clean baseline
make inject FAILURE=<key> [RECORD=1]     # optional: corrupt the source (silent unless RECORD=1)
make land                                # Postgres -> DuckDB raw.* via ATTACH
```

The trace:

1. **`make up`** — Postgres boots and auto-applies `01_schema.sql`, creating
   `public.{customers,products,orders,payments}` and an empty
   `_control.injected_incidents`.
2. **`make seed`** — `EcommerceFactory` builds correlated rows; `insert_returning_ids`
   loads customers → products → orders → payments in one committed transaction.
   Writes **only** `public.*`.
3. **(optional) `make traffic` / `inject` / `watch`** — mutate the source. The
   ledger is written **only** when `RECORD=1`.
4. **`make land`** — resolve schema drift via `information_schema`; stamp a single
   `_ingested_at = now(UTC)`; `ATTACH` Postgres `READ_ONLY` via the `postgres`
   extension with a temporary secret scoped to `SCHEMA 'public'`; `CREATE SCHEMA raw`;
   per entity `CREATE OR REPLACE TABLE raw.raw_<entity> AS SELECT ...`. It reads
   **only** `pg.public.*`, never `_control`. It finishes with `DETACH` + `DROP SECRET`.

### Tables present at each hop

| Hop                              | Store    | Schemas / tables |
|----------------------------------|----------|------------------|
| after `make up`                  | Postgres | `public.customers/products/orders/payments`; `_control.injected_incidents` (empty) |
| after `make seed`                | Postgres | `public.*` populated; `_control` empty |
| after `make inject ... RECORD=1` | Postgres | `public.*` corrupted; one row in `_control.injected_incidents` |
| after `make land`                | DuckDB   | `raw.raw_customers/products/orders/payments` (`_control` is **never** landed — `ATTACH` is `SCHEMA 'public'` only) |

---

## The Postgres schema

`db/01_schema.sql` defines four business tables in `public`. All use a
`BIGINT IDENTITY` primary key, money as `NUMERIC` with a non-negative `CHECK`, and
timestamps as `TIMESTAMPTZ`.

**`customers`**

| Column        | Type / constraint |
|---------------|-------------------|
| `customer_id` | `BIGINT` PK |
| `full_name`   | text |
| `email`       | text, `UNIQUE` |
| `country`     | text |
| `city`        | text |
| `segment`     | text |
| `created_at`  | `TIMESTAMPTZ` DEFAULT `now()` |

**`products`**

| Column       | Type / constraint |
|--------------|-------------------|
| `product_id` | `BIGINT` PK |
| `sku`        | text, `UNIQUE` |
| `name`       | text |
| `category`   | text |
| `unit_price` | `NUMERIC(10,2)` ≥ 0 |
| `cost`       | `NUMERIC(10,2)` ≥ 0 |
| `created_at` | `TIMESTAMPTZ` DEFAULT `now()` |

**`orders`**

| Column         | Type / constraint |
|----------------|-------------------|
| `order_id`     | `BIGINT` PK |
| `customer_id`  | `BIGINT` FK → `customers` |
| `product_id`   | `BIGINT` FK → `products` |
| `quantity`     | `INT` > 0 |
| `unit_price`   | `NUMERIC(10,2)` ≥ 0 |
| `total_amount` | `NUMERIC(12,2)` ≥ 0 |
| `status`       | text |
| `ordered_at`   | `TIMESTAMPTZ` |

**`payments`**

| Column       | Type / constraint |
|--------------|-------------------|
| `payment_id` | `BIGINT` PK |
| `order_id`   | `BIGINT` FK → `orders` |
| `method`     | text |
| `amount`     | `NUMERIC(12,2)` ≥ 0 |
| `status`     | text |
| `paid_at`    | `TIMESTAMPTZ` |

Indexes: `idx_orders_customer_id`, `idx_orders_product_id`, `idx_orders_ordered_at`,
`idx_payments_order_id`.

**The `_control` fence.** A separate schema holds the answer key:
`_control.injected_incidents(incident_id PK, failure_key, detail, injected_at DEFAULT now())`
plus indexes. The DDL comment states the intent plainly: the ledger is a
facilitator-only artifact, written **only** with `--record` / `RECORD=1` and read
only at the reveal. The source database the analytics read looks exactly like real
production — there is no incident table in `public` to give the game away.

---

## The DuckDB landing contract

`transition/ingest.py` lands each source entity into `raw.*`. Defects are **never**
dropped or repaired here — they land intact in `raw.*`.

### Entity specs

| Entity      | Source table | Primary key  | Watermark column |
|-------------|--------------|--------------|------------------|
| `customers` | `customers`  | `customer_id`| `created_at` |
| `products`  | `products`   | `product_id` | `created_at` |
| `orders`    | `orders`     | `order_id`   | `ordered_at` |
| `payments`  | `payments`   | `payment_id` | `paid_at` |

`ALL_SPECS` orders them customers, products, orders, payments — for output
readability only.

### The three stamp columns

Every landed row carries run-level lineage columns appended after the source columns:

| Column              | Meaning |
|---------------------|---------|
| `_ingested_at`      | One tz-aware UTC instant (`datetime.now(UTC)`) shared by every row of every table in the run — the freshness anchor. Bound as a parameter, never `now()` in SQL (which would strip the timezone). |
| `_source_watermark` | The run's high-watermark `max(<watermark_col>)` from the source, identical on every row of the entity, `NULL` on an empty source. |
| `_schema_drift`     | **orders only.** A bound boolean, `TRUE` when the source link column drifted to `user_id`. The other three tables omit this column — the source DDL asymmetry is preserved. |

### Schema-drift resolution

The orders source column can rename from `customer_id` to `user_id` (the
`schema_drift` defect). `transition` resolves the live column **once**, before any
`ATTACH`, via a read-only `information_schema` probe with a 10-second timeout (a
mirror of `repository.order_customer_column`, defaulting to `customer_id`). That one
resolved value drives **both** the templated `<live_col> AS customer_id` identifier
and the bound `_schema_drift` boolean, so the identifier and the flag can never
disagree. Identifiers can't be bound, so the column — sourced from
`information_schema`, never user input — is templated into the projection.

### Mechanics

- **Full refresh, not incremental.** No watermark state, no `MERGE` / `ON CONFLICT`,
  no lookback window. `CREATE OR REPLACE TABLE` makes re-runs idempotent (apart from
  `_ingested_at`, which advances by design). A failure mid-run leaves already-landed
  tables intact and propagates loudly.
- **`READ_ONLY` ATTACH.** `ATTACH '' AS pg (TYPE postgres, READ_ONLY, SECRET pg_landing, SCHEMA 'public')`.
  `READ_ONLY` enforces the one-way dependency; `SCHEMA 'public'` is why `_control`
  is never visible to the landing.
- **Secret handling.** The Postgres password lives in a `TEMPORARY` DuckDB secret —
  never in the `ATTACH` string and never in error output. Secret values are escaped
  by doubling quotes. The secret is dropped in a `finally` alongside the `DETACH`, so
  a mid-run error still cleans up.
- **Type fidelity.** `NUMERIC → DECIMAL`, `TIMESTAMPTZ → TIMESTAMP WITH TIME ZONE`.
  Money is never cast — `DECIMAL` stays `DECIMAL`, timestamps stay tz-aware.
- The warehouse connection itself is read/write (it writes `raw.*`); only the
  Postgres `ATTACH` is read-only.

---

## The warehouse contract

`warehouse/paths.py` + `connection.py` own the single DuckDB file and the connection
contract. Nothing else in the repo hardcodes a warehouse path or opens its own
DuckDB connection.

DuckDB is an **embedded, in-process library** — a single local file, not a server or
container. Only Postgres is containerized.

### The `DUCKDB_DATABASE` rule

The warehouse location is configured **exclusively** via the `DUCKDB_DATABASE`
environment variable:

- **Only that name.** Legacy names `DUCKDB_PATH` and `WAREHOUSE_DB_PATH` are
  rejected — if either is set without `DUCKDB_DATABASE`, resolution raises
  `RuntimeError`, so misconfiguration fails loud rather than silently writing to the
  wrong place.
- **Unset** → the default file `src/warehouse/warehouse.duckdb` (gitignored).
  `paths.py` is the only place that literal exists.
- **A filesystem path** → resolved to its absolute form.
- **MotherDuck escape hatch** → a value starting with `md:` (or `motherduck:`) is
  honoured verbatim and never resolved to a filesystem path. `warehouse_path_str()`
  returns it as-is; `warehouse_path()` raises `ValueError`, since a DSN has no file
  path.

### Connecting

`connection.py` exposes the only sanctioned ways to open the warehouse:

- `connect(read_only=False)` — read/write. Writers (the `transition` landing step,
  dbt) use this; it ensures the parent directory exists before opening.
- `connect_read_only()` — read-only convenience (`access_mode=READ_ONLY`). Readers
  use this; the parent is **not** auto-created, so a missing file surfaces as an
  error rather than a silently-created empty DB.
- `connection(...)` — a context-managed handle that always closes.

### Single-writer concurrency

DuckDB is **single-writer-process**. Writers open `connect()` briefly and never
concurrently — serialized by the orchestration order (land, then transform).
Read-only readers may run concurrently with each other and with a single writer.
Keeping every connection behind these helpers is what makes that invariant
enforceable in one place.

---

## The generator & failures

`src/gen` injects 14 generic defects into the source. Each injector knows what it
corrupts and nothing about who consumes it.

| Key                     | Summary                                                      | Touches |
|-------------------------|--------------------------------------------------------------|---------|
| `negative_price`        | order with negative `unit_price` + `total`                   | orders |
| `missing_customer`      | order with NULL customer column                              | orders |
| `invalid_quantity`      | order with `quantity = -5`                                   | orders |
| `duplicate_order`       | re-insert the latest order verbatim                          | orders |
| `late_arrival`          | order backdated 45 days                                      | orders |
| `volume_spike`          | burst of 500 orders at one timestamp                         | orders |
| `schema_drift`          | rename `orders.customer_id` → `user_id` (idempotent)         | orders schema |
| `orphan_payment`        | drop FK, payment for `order_id = 999999999`                  | payments |
| `recurring_incident`    | re-inject negative price, reports occurrence number          | orders + reads ledger |
| `ambiguous_anomaly`     | 200 orders cancelled + 20 products price-cut 50%             | orders + products |
| `destructive_fix`       | zero `total_amount` on 300 recent orders                     | orders |
| `malformed_data`        | garbage string into `status` on 25 orders                    | orders |
| `slow_source`           | `pg_sleep(8)` holding a lock, `lock_timeout = 1s`            | orders availability |
| `multi_failure_cascade` | fires `missing_customer` + `volume_spike` + `schema_drift`   | orders schema + rows |

**Guards.** Several injectors call `_disable_order_checks()` first — it drops
`orders_unit_price_check` / `quantity_check` / `total_amount_check` plus the customer
`NOT NULL`, all `IF EXISTS` and idempotent. The customer column is resolved
dynamically so injectors tolerate prior drift.

**Silent by default.** `Failure.inject()` returns `InjectionResult(failure, detail)`
and writes nothing. `repo.record_incident()` is the only writer to
`_control.injected_incidents`, called only when `record=True` (CLI `--record`,
Makefile `RECORD=1` → `--record`). `engine.inject` special-cases the cascade
(threading `record` in; the cascade owns its own writes — no double write).
`count_incidents` returns `0` when silent.

**CLI surface.**

| Command                | What it does |
|------------------------|--------------|
| `list`                 | List the available failure modes |
| `traffic --orders N`   | Insert N normal orders (default 200) |
| `inject <failure> [--record]` | Inject one defect; `--record` writes the ledger |
| `reset-schema`         | Revert schema drift (`user_id` → `customer_id`) — the only built-in drift restore |
| `watch [...]`          | Stream traffic + random failures (`--interval 3.0 --batch 50 --failure-every 5 --failures... --record`) |

---

## Conventions

- **Determinism is selective.** The seed baseline is reproducible via `Faker.seed` —
  the same seed gives the same clean dataset. Generator traffic is **intentionally
  not** seeded; it is nondeterministic, like real production traffic.
- **Money and time are exact, end to end.** Money is `Decimal` cents; timestamps are
  tz-aware UTC. The fidelity is preserved across `ATTACH` — `NUMERIC → DECIMAL`,
  `TIMESTAMPTZ → TIMESTAMP WITH TIME ZONE`, money never cast.
- **No hardcoded secrets; parameterized SQL only.** Postgres credentials come from
  `POSTGRES_*` env; the DuckDB password lives in a temporary secret kept out of error
  output. All SQL parameters use placeholders; identifiers are interpolated only from
  internal constants or `information_schema`, never from user input.
- **One-directional dependency.** Postgres is the containerized, mutable source;
  DuckDB is the embedded, append-on-refresh store; `transition` is the only crossing,
  and it `ATTACH`es `READ_ONLY`. The source never depends on the warehouse.

---

## Verified end-to-end

The full pipeline was run on a clean slate and confirmed working:

- **`make seed`** → Postgres: `customers=500`, `products=200`, `orders=5000`,
  `payments=5000`.
- **`make land`** → DuckDB `raw.*`: `raw_customers=500`, `raw_products=200`,
  `raw_orders=5000`, `raw_payments=5000` — exact row parity with Postgres.
- **Fencing confirmed.** `public` holds only the four business tables;
  `_control.injected_incidents` is separate and never landed — the warehouse has only
  the `raw` schema.
- **Integrity preserved.** Order total = `quantity × unit_price` (e.g.
  `6 × 142.37 = 854.22`); returned/cancelled orders map to refunded payments;
  `DECIMAL` money survives the `ATTACH`; every run carries a single `_ingested_at`,
  a per-entity `_source_watermark`, and `_schema_drift = False` on a clean baseline
  (and only `orders` carries that column).

A two-row illustration of a landed `raw.raw_orders` on a clean baseline:

| `order_id` | `customer_id` | `quantity` | `unit_price` | `total_amount` | `status` | `_ingested_at` | `_source_watermark` | `_schema_drift` |
|------------|---------------|------------|--------------|----------------|----------|----------------|---------------------|-----------------|
| 1          | 411           | 6          | 142.37       | 854.22         | cancelled | (run instant) | (max `ordered_at`) | `false` |
| 2          | 447           | 5          | 439.68       | 2198.40        | returned  | (run instant) | (max `ordered_at`) | `false` |

These are the actual first two landed rows from the verification run (with the
default `--seed 42` baseline). Note that `total_amount = quantity × unit_price`
holds (`6 × 142.37 = 854.22`, `5 × 439.68 = 2198.40`), `_ingested_at` is the same
instant on every row of the run, and `_source_watermark` is identical per entity.
