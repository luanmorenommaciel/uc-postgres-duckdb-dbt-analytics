# uc-postgres-duckdb-dbt-analytics

The analytics **brownfield base** for an AI-native DataOps workshop. A high-volume
e-commerce company runs its storefront and its analytics on one Postgres database;
the two workloads fight for the same resources. This repo is the deterministic
foundation that the rest of the platform is built on, live, during the workshop.

What ships here is small and honest:

- a **Postgres** source schema (auto-applied on first boot),
- a **deterministic seeder** that produces a clean, correlated baseline,
- a **14-mode chaos generator** that injects realistic failures (and can log
  ground truth to an `injected_incidents` ledger), and
- a **landing step** that pulls Postgres into a **DuckDB** warehouse via `ATTACH`,
  giving you `raw.*` tables to transform downstream.

## Architecture

```
  src/gen ──inject──▶ ┌────────────┐   make land    ┌──────────────────────┐
  src/seed ──seed──▶  │  Postgres  │ ──ATTACH/copy─▶ │  DuckDB warehouse     │
                      │  (source)  │                 │  raw.*  (analytics)   │
                      └────────────┘                 └──────────────────────┘
                            │
                            └─ injected_incidents  (ground-truth ledger, opt-in)
```

Postgres is the operational source. `make land` ATTACHes it from DuckDB and copies
the source tables into `raw.*` inside a single DuckDB file
(`platform/warehouse/warehouse.duckdb` by default; override with `DUCKDB_DATABASE`).
That warehouse file is the seam everything downstream reads from.

## Quickstart

```bash
make setup                       # uv sync — install deps
cp .env.example .env             # configure Postgres + warehouse env
make up                          # start Postgres (schema auto-applied)
make seed                        # deterministic clean baseline
make land                        # Postgres -> DuckDB raw.* via ATTACH

make inject FAILURE=schema_drift # inject a failure (SILENT by default)
make failures                    # list all 14 failure modes
```

### Silent failures and the ledger

Injection is **silent by default**: `make inject FAILURE=<key>` mutates the source
but writes **nothing** to the `injected_incidents` ledger — the failure is in the
data, undeclared, exactly as a real incident would arrive. To record ground truth
(so a future detector can be scored against it), opt in:

```bash
make inject FAILURE=schema_drift RECORD=1   # also writes the injected_incidents row
```

Keeping the default silent is deliberate: the ledger is the scoring oracle, and a
detector that can already see the answer key proves nothing.

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
| `inject`       | Inject one failure SILENTLY (`FAILURE=`); add `RECORD=1` to log the ledger |
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
- **Sentinel** — the agent crew that watches the backbone, diagnoses injected
  failures, and is scored against the `injected_incidents` ledger.
