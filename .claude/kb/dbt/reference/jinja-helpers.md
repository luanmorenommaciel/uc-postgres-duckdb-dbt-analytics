# Reference · Jinja Helpers

> **Scope:** The dbt-specific Jinja functions a model author calls in THIS repo —
> `ref()`, `source()`, `config()`, plus the supporting `this`, `var()`, `env_var()`,
> `is_incremental()`. These are what wire the medallion graph (bronze→silver→gold)
> together; the developer agent greps here for exact signatures.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below is traceable to one of these. Refreshed 2026-06-25.

- dbt Jinja functions index: https://docs.getdbt.com/reference/dbt-jinja-functions
- `ref()`: https://docs.getdbt.com/reference/dbt-jinja-functions/ref
- `source()`: https://docs.getdbt.com/reference/dbt-jinja-functions/source
- `config()`: https://docs.getdbt.com/reference/dbt-jinja-functions/config
- `this`: https://docs.getdbt.com/reference/dbt-jinja-functions/this
- `var()`: https://docs.getdbt.com/reference/dbt-jinja-functions/var
- `env_var()`: https://docs.getdbt.com/reference/dbt-jinja-functions/env_var
- `is_incremental()`: https://docs.getdbt.com/reference/dbt-jinja-functions/is_incremental
- Materializations (for `config(materialized=...)`): https://docs.getdbt.com/docs/build/materializations
- Verified against: dbt Core 1.x docs (current), 2026-06-25

## Core graph functions

| Call | Returns | Side effect | Use in THIS repo |
|------|---------|-------------|------------------|
| `ref('model_name')` | `Relation` | Adds a DAG edge to that model | silver→`ref('bronze_orders')`; gold→`ref('silver_orders')` |
| `ref('package', 'model_name')` | `Relation` | Cross-package edge | Not used (single project) |
| `source('source_name', 'table')` | `Relation` | Adds a DAG edge to a declared source | bronze→`source('raw', 'raw_orders')` |
| `config(key=value, ...)` | `''` (sets config) | Configures the current model | per-model overrides of `+materialized`/`+schema`/`tags` |
| `this` | `Relation` for the current model | none | self-reference inside incremental `WHERE` |
| `var('name'[, default])` | value | none | read `vars:` from `dbt_project.yml` |
| `env_var('NAME'[, default])` | string | none | read env (e.g. `DUCKDB_DATABASE`) |
| `is_incremental()` | bool | none | guards the incremental delta predicate |

### `ref()` — the spine of the graph

```sql
-- transform/models/silver/silver_orders.sql
select * from {{ ref('bronze_orders') }}
```

`ref()` does two things: it interpolates the deployment schema (so `bronze_orders`
resolves to `bronze.bronze_orders` here) and it records the edge dbt uses to order the
build. Never hardcode a schema-qualified relation for an in-project model — use `ref()`
so the DAG and `dbt build` ordering stay correct.
Source: https://docs.getdbt.com/reference/dbt-jinja-functions/ref

### `source()` — the only door to `raw.*`

```sql
-- transform/models/bronze/bronze_orders.sql
select * from {{ source('raw', 'raw_orders') }}
```

`source()` resolves against `sources.yml`. Bronze is the **only** layer that calls
`source()`; silver and gold reach raw transitively through `ref()`. Reading `raw.*`
directly (without a declared source) breaks freshness and lineage.
Source: https://docs.getdbt.com/reference/dbt-jinja-functions/source

### `config()` — per-model overrides

```sql
{{ config(
    materialized='table',
    schema='gold',
    tags=['gold', 'contract']
) }}
```

In-model `config()` overrides the path-level `+`-config from `dbt_project.yml` for that
one model. Valid `materialized` values: `view`, `table`, `incremental`,
`ephemeral`, `materialized_view` (plus adapter/custom).
Source: https://docs.getdbt.com/reference/dbt-jinja-functions/config and
https://docs.getdbt.com/docs/build/materializations

## Cross-references

- `quick-reference.md` — this tech's index
- `dbt-yaml-schema.md` — the YAML these functions resolve against (`sources.yml`, model configs)
- `patterns/ref-graph-discipline.md` — how `ref()`/`source()` compose into the bronze→silver→gold DAG
- `concepts/models-and-materializations.md` — view-vs-table choice per layer (cited-TODO stub)
