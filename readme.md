# uc-postgres-duckdb-dbt-analytics

The analytics **brownfield base** for an AI-native DataOps workshop. A high-volume
e-commerce company runs its storefront and its analytics on one Postgres database;
the two workloads fight for the same resources. This repo is the deterministic
foundation that the rest of the platform is built on, live, during the workshop.

What ships here is small and honest:

- a **Postgres** source schema (auto-applied on first boot),
- a **deterministic seeder** that produces a clean, correlated baseline,
- a **14-mode chaos generator** that injects generic data-quality, schema, and
  availability defects into the source — and can log ground truth to a fenced
  `_control.injected_incidents` ledger that lives **outside** the `public`
  business tables, and
- a **transition step** (`src/transition`) that pulls Postgres into a **DuckDB**
  warehouse via `ATTACH`, giving you `raw.*` tables to transform downstream.

Postgres is containerized; **DuckDB is not** — it is an embedded, in-process
library backed by a single local file. There is no DuckDB server or container.

## What the pipeline actually is

Three steps, one direction. The generator seeds (and corrupts) the operational
**Postgres** source; `make land` `ATTACH`es Postgres read-only from **DuckDB** and
copies the business tables into `raw.*`; everything downstream reads the warehouse.

```mermaid
graph LR
    G([make seed / inject]) --> P[(Postgres<br/>public.*)]
    P -->|make land · ATTACH read-only| W[(DuckDB<br/>raw.*)]
    W --> D([transform / serve<br/>built live])
    C[(Postgres<br/>_control.*)] -.never landed.- W
```

The source `public` schema holds only the four business tables — it looks like a
real production database, with no incident table to give the game away. The
ground-truth ledger lives in a separate `_control` schema the warehouse never
reads (the dotted edge): a sealed answer key, written only with `RECORD=1`.

## Architecture

The source crosses into the analytical store exactly once, through `src/transition`.
`src/db` and `src/warehouse` are the two leaves everything else depends on.

```mermaid
graph LR
    SEED[src/seed<br/>clean baseline] --> DB
    GEN[src/gen<br/>traffic + 14 defects] --> DB
    DB[(src/db<br/>Postgres · public + _control)]
    DB -->|ATTACH read-only| T[src/transition<br/>land raw.*]
    T --> WH[(src/warehouse<br/>DuckDB file)]
    GEN -.RECORD=1.- LEDGER[(_control<br/>answer key)]
    LEDGER -.never landed.- WH
```

| Package          | Role |
|------------------|------|
| `src/db`         | Postgres connection + schema (`01_schema.sql`) — the operational source |
| `src/seed`       | Deterministic clean baseline (correlated synthetic data) |
| `src/gen`        | 14-mode chaos generator + fenced `_control.injected_incidents` ledger |
| `src/transition` | Postgres -> DuckDB `raw.*` movement via `ATTACH` (full refresh) — the only bridge |
| `src/warehouse`  | The single embedded DuckDB file + the connection contract |

`make land` runs `src/transition`, which `ATTACH`es Postgres read-only from DuckDB
and copies the source tables into `raw.*` inside a single embedded DuckDB file
(`src/warehouse/warehouse.duckdb` by default; override with `DUCKDB_DATABASE`).
That warehouse file is the seam everything downstream reads from. See
[`src/README.md`](src/README.md) for the per-package deep dive — the schema, the
landing contract, the warehouse contract, and the 14 failure modes.

## Quickstart

```bash
make setup                       # uv sync — install deps
cp .env.example .env             # configure Postgres + warehouse env
make up                          # start Postgres (schema auto-applied)
make seed                        # deterministic clean baseline
make land                        # Postgres -> DuckDB raw.* via ATTACH

make inject FAILURE=schema_drift # inject a defect (SILENT by default)
make failures                    # list all 14 failure modes
```

The operator loop — set up once, then cycle seed → land → inspect → reset:

```mermaid
graph LR
    A([make up]) --> B[make seed]
    B --> C[make land]
    C --> E{inspect<br/>Postgres + DuckDB}
    E -->|inject a defect| D[make inject]
    D --> C
    E -->|start clean| F([make reset])
    F --> B
```

### Silent failures and the fenced answer key

Injection is **silent by default**: `make inject FAILURE=<key>` mutates the source
but writes **nothing** to the ledger — the defect lives only in the data,
undeclared, exactly as a real incident would arrive. You investigate it the way an
on-call engineer does: notice the numbers are off, then go digging. To record
ground truth (so a future detector can be *scored* against it, not just sound
plausible), opt in:

```bash
make inject FAILURE=schema_drift RECORD=1   # also writes _control.injected_incidents
```

Two things make this realistic:

- **The answer key is fenced.** It lives in a separate `_control` schema, never in
  `public`. The business tables the analytics read have no incident table — the
  source looks exactly like production. `_control` is also never copied into the
  DuckDB warehouse.
- **Silent by default is deliberate.** The ledger is the scoring oracle (the sealed
  envelope), opened only at the reveal. A detector that can already see the answer
  key proves nothing.

## Make targets

| Target         | What it does |
|----------------|--------------|
| `setup`        | Install Python dependencies with `uv` |
| `up`           | Start PostgreSQL; wait until healthy (schema auto-applied) |
| `down`         | Stop containers, keep data |
| `restart`      | `down` then `up` |
| `logs`         | Tail PostgreSQL logs |
| `ps`           | Show container status |
| `psql`         | Open a `psql` shell against the source database |
| `seed`         | Generate a clean correlated dataset (`CUSTOMERS/PRODUCTS/ORDERS/SEED`) |
| `reseed`       | Truncate then regenerate a fresh clean dataset |
| `reset`        | Destroy the data volume and recreate an empty database |
| `clean`        | Remove containers and the data volume |
| `failures`     | List the available failure modes |
| `traffic`      | Insert normal orders (`TRAFFIC=count`) |
| `inject`       | Inject one defect SILENTLY (`FAILURE=`); add `RECORD=1` to log the ledger |
| `reset-schema` | Revert schema drift (`user_id` -> `customer_id`) |
| `watch`        | Stream traffic and inject random failures (Ctrl-C to stop) |
| `land`         | Land Postgres into DuckDB via `ATTACH` (`raw.*`) |
| `test`         | Run the `pytest` suite |
| `lint`         | Lint with `ruff` |

Variables you can override on any `make` call: `CUSTOMERS`, `PRODUCTS`, `ORDERS`,
`SEED`, `FAILURE`, `TRAFFIC`, `RECORD`.

## What's intentionally NOT here yet (built live)

This is the base. The following layers are added during the workshop and are
deliberately absent so they can be built from first principles:

- **dbt** — the Medallion (bronze/silver/gold) transformation over `raw.*`.
- **FastAPI / MCP** — the intelligence layer that serves the warehouse.
- **Detection / scoring** — whatever watches the backbone, diagnoses the injected
  defects, and is scored against the `injected_incidents` ledger.
