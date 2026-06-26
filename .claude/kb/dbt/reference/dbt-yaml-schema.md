# Reference · Dbt Yaml Schema

> **Scope:** The YAML surface a dbt-duckdb project touches in THIS repo —
> `dbt_project.yml`, the dbt-duckdb `profiles.yml` block, `sources.yml`, and the
> per-resource `schema.yml` (model properties, configs, tests, contract). This is the
> seam the gold marts ship to Component B.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below is traceable to one of these. Refreshed 2026-06-25.

- `dbt_project.yml` reference: https://docs.getdbt.com/reference/dbt_project.yml
- Configs vs. properties (where each key is legal): https://docs.getdbt.com/reference/configs-and-properties
- Resource properties (models, columns, sources): https://docs.getdbt.com/reference/configs-and-properties
- Out-of-the-box data tests: https://docs.getdbt.com/reference/resource-properties/data-tests
- Data tests (build): https://docs.getdbt.com/docs/build/data-tests
- Materializations: https://docs.getdbt.com/docs/build/materializations
- Model contract (`contract: {enforced: true}`): https://docs.getdbt.com/reference/resource-configs/contract
- dbt-duckdb profile + adapter configs: https://github.com/duckdb/dbt-duckdb  and  https://docs.getdbt.com/reference/resource-configs/duckdb-configs
- Verified against: dbt Core 1.x / dbt-duckdb (master README, 2026-06-25)

## `dbt_project.yml` — top-level keys

| Key | Purpose | Notes |
|-----|---------|-------|
| `name` | Project name (snake_case) | Referenced under `models:` |
| `version` | Project version string | Required |
| `profile` | Which `profiles.yml` profile to use | Must match the profile name |
| `model-paths` | Where models live | Default `["models"]` |
| `seed-paths` / `test-paths` / `macro-paths` / `snapshot-paths` | Resource dirs | Defaults are the plural names |
| `target-path` / `clean-targets` | Build artifact dirs | `dbt clean` removes `clean-targets` |
| `models:` | Per-path config tree | Set `+materialized`, `+schema`, `+tags`, etc. here |
| `vars:` | Project variables | Read in Jinja via `var('name')` |

Source: https://docs.getdbt.com/reference/dbt_project.yml

### Per-path model config (medallion shape for THIS repo)

```yaml
models:
  uc_analytics:
    bronze:
      +materialized: view        # lossless typing off raw.*, zero storage
      +schema: bronze
    silver:
      +materialized: table       # conformed; gold reads it repeatedly
      +schema: silver
    gold:
      +materialized: table       # marts; the schema.yml here is the contract
      +schema: gold
```

`+`-prefixed keys are configs applied to every model under that path; the bare keys
(`bronze`, `silver`, `gold`) are folder names under `model-paths`.
Source: https://docs.getdbt.com/reference/configs-and-properties

## dbt-duckdb `profiles.yml` block

| Key | Purpose | Notes |
|-----|---------|-------|
| `type` | Adapter | Must be `duckdb` |
| `path` | DuckDB file path | Persist relations; `:memory:` for in-memory. **In THIS repo resolve from `DUCKDB_DATABASE` via `src/warehouse`, never a literal** |
| `database` | Catalog name | **Auto-derived** from `path` basename minus suffix; do not hand-set |
| `schema` | Default target schema | Per-model `+schema` overrides |
| `threads` | Parallelism | dbt runs serialized here (single-writer) |
| `extensions` | DuckDB extensions to load | List of strings or `name`/`repo` pairs |
| `settings` | DuckDB config options | Passed to the connection |
| `attach` | Additional databases (1.4.0+) | `path`/`alias`/`type`/`read_only` |

```yaml
default:
  outputs:
    dev:
      type: duckdb
      path: "{{ env_var('DUCKDB_DATABASE') }}"
      threads: 1
  target: dev
```

Source: https://github.com/duckdb/dbt-duckdb (Configuring Your Profile)

## `sources.yml` — declaring `raw.*`

| Key | Level | Purpose |
|-----|-------|---------|
| `sources:` | top | List of source groups |
| `name` | source | Logical source name, used as `source('<name>', '<table>')` |
| `schema` | source | Physical schema (`raw`) if it differs from `name` |
| `database` | source | Catalog override (DuckDB attach/basename) |
| `tables:` | source | List of table entries |
| `freshness:` | source/table | `warn_after` / `error_after` with `count` + `period` |
| `loaded_at_field` | source/table | Column freshness is measured against |

```yaml
sources:
  - name: raw
    schema: raw
    tables:
      - name: raw_orders
      - name: raw_payments
      - name: raw_customers
      - name: raw_products
```

Source: https://docs.getdbt.com/reference/configs-and-properties (source properties);
freshness: https://docs.getdbt.com/docs/build/data-tests

## `schema.yml` — model properties, configs, tests, contract

| Key | Level | Purpose |
|-----|-------|---------|
| `models:` | top | List of model property blocks |
| `name` | model | Must match the model file name |
| `description` | model/column | Docs surface |
| `config:` | model | Inline configs (`materialized`, `tags`, `contract`, …) |
| `columns:` | model | Per-column properties + tests |
| `data_tests:` | column/model | Tests to run (key is `data_tests`; legacy alias `tests`) |
| `contract:` | model `config` | `enforced: true` ⇒ dbt checks declared column names + `data_type` at build |

### Out-of-the-box data tests (the only four built in)

| Test | Level | Asserts |
|------|-------|---------|
| `not_null` | column | No NULLs in the column |
| `unique` | column | No duplicate values |
| `accepted_values` | column | Every non-NULL value is in `values: [...]` |
| `relationships` | column | Every value maps to `to: ref(...)` / `field:` (referential integrity) |

`accepted_values` and `relationships` take their parameters under an `arguments:`
block in dbt v1.10.5+ (older versions put them at the top level).
Source: https://docs.getdbt.com/reference/resource-properties/data-tests

### The gold contract block (Component A owns this, B compiles against it)

```yaml
models:
  - name: gold_revenue_by_category
    config:
      contract:
        enforced: true          # build fails if a declared column is missing/mistyped
    columns:
      - name: category
        data_type: varchar
        data_tests: [not_null]
      - name: order_date
        data_type: date
        data_tests: [not_null]
      - name: revenue
        data_type: decimal(18,2)   # money stays DECIMAL — never recast to float
        data_tests: [not_null]
```

When `contract.enforced: true`, every column a model produces must be declared with a
`data_type`, and dbt validates the shape at build time — this is what makes `schema.yml`
a binding interface rather than documentation.
Source: https://docs.getdbt.com/reference/resource-configs/contract

## Cross-references

- `quick-reference.md` — this tech's index
- `jinja-helpers.md` — `ref()`/`source()`/`config()` that wire these YAML resources together
- `patterns/ref-graph-discipline.md` — how the per-layer `+materialized`/`+schema` configs above compose into a clean graph
- `concepts/tests-and-sources.md` — deeper treatment of sources + tests (cited-TODO stub)
