# Pattern · Ref Graph Discipline

> **Solves:** Keeping the medallion DAG acyclic and layer-respecting — every model reads
> only the layer directly below it (bronze→source, silver→bronze, gold→silver), never
> skipping or reaching sideways. This is what makes `dbt build` order correct and the
> gold contract trustworthy.
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- dbt project structure (staging → intermediate → marts): https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview
- `ref()`: https://docs.getdbt.com/reference/dbt-jinja-functions/ref
- `source()`: https://docs.getdbt.com/reference/dbt-jinja-functions/source
- Node selection (validate the graph): https://docs.getdbt.com/reference/node-selection/syntax
- Verified against: dbt Core 1.x docs (current), 2026-06-25

## Problem

The repo's medallion has three layers (bronze→silver→gold) over the frozen `raw.*`
tables. dbt's canonical structure is staging → intermediate → marts, where **each layer
reads only the one below it via `ref()`/`source()`**. Map them directly: bronze is the
staging layer (1 view per source, lossless typing), silver is intermediate (conform +
quarantine the 14 defects, tables), gold is marts (business aggregates + the per-mart
`schema.yml` contract Component B compiles against).

The failure mode this pattern prevents: a model that reaches **past** its layer — gold
selecting from `bronze_orders` or `source('raw','raw_orders')` directly. That bypasses
silver's defect quarantine, so quarantined rows (`negative_price`, `duplicate_order`,
out-of-vocab status) leak into a money mart and silently overcount revenue. It also
hardcodes a relation that `ref()` should resolve, breaking lineage and build ordering.

## Pattern

One `ref()`/`source()` rule per layer. Each model's `FROM` only ever names the layer
directly below.

```sql
-- BRONZE (staging): the ONLY layer that calls source(). View, lossless.
-- transform/models/bronze/bronze_orders.sql
{{ config(materialized='view', schema='bronze') }}

select
    order_id,
    customer_id,
    product_id,
    quantity,
    unit_price,                         -- DECIMAL preserved, never recast
    total_amount,
    lower(trim(status))   as status,    -- normalize text only
    ordered_at,                         -- tz-aware preserved
    _ingested_at,
    _source_watermark,
    _schema_drift                       -- defect rows pass through, tagged
from {{ source('raw', 'raw_orders') }}
```

```sql
-- SILVER (intermediate): reads bronze via ref() ONLY. Table. Conforms + quarantines.
-- transform/models/silver/silver_orders.sql
{{ config(materialized='table', schema='silver') }}

with ranked as (
    select *,
        row_number() over (
            partition by customer_id, product_id, quantity,
                         unit_price, total_amount, ordered_at   -- business signature
            order by order_id                                   -- keep lowest order_id
        ) as _rn
    from {{ ref('bronze_orders') }}                             -- one layer below
)
select * exclude (_rn)
from ranked
where _rn = 1
  and total_amount = quantity * unit_price                      -- money invariant
  and unit_price >= 0 and quantity > 0
  and status in ('placed','shipped','delivered','returned','cancelled')
```

```sql
-- GOLD (marts): reads silver via ref() ONLY. Table. Aggregates clean rows.
-- transform/models/gold/gold_revenue_by_category.sql
{{ config(materialized='table', schema='gold') }}

select
    p.category,
    o.ordered_at::date        as order_date,
    sum(o.total_amount)       as revenue          -- DECIMAL aggregate, no NULLs
from {{ ref('silver_orders') }}   o                -- never bronze, never raw
join {{ ref('silver_products') }} p using (product_id)
where o.status <> 'cancelled'
group by 1, 2
```

The matching `schema.yml` makes gold a contract (see `reference/dbt-yaml-schema.md` for
the full `contract: {enforced: true}` block).

## Why this shape

- **`ref()` builds the DAG.** dbt orders `dbt build` from the `ref()`/`source()` edges,
  so a correct edge set *is* a correct build order — no manual sequencing.
  (https://docs.getdbt.com/reference/dbt-jinja-functions/ref)
- **One door to raw.** Only bronze calls `source()`. That single seam is where
  freshness, lineage, and "we never write back to Postgres" are enforced — everything
  above reaches raw transitively and read-only.
- **Layer isolation = correctness isolation.** Because gold can only `ref()` silver, the
  defect quarantine in silver is unbypassable: there is no syntactic path from a money
  mart back to a defect row. The obvious alternative (gold reads bronze for "speed")
  re-opens that path and the eval (`gold_revenue == silver source`) fails.

## Anti-patterns

- **Layer-skip:** gold selecting `{{ ref('bronze_orders') }}` or
  `{{ source('raw','raw_orders') }}`. Bypasses silver's quarantine → defects inflate the
  mart. The repo's reconciliation eval catches it, but the fix is structural: only
  `ref()` the layer below.
- **Hardcoded relations:** `from raw.raw_orders` or `from silver.silver_orders` as a bare
  string instead of `source()`/`ref()`. No DAG edge → wrong build order, broken lineage,
  and the deployment schema can't be re-pointed.
- **Sideways / cyclic refs:** two silver models `ref()`-ing each other, or a bronze model
  `ref()`-ing a gold model. dbt raises a cycle error; even when it parses, it signals the
  layers are wrong.
- **Writing back to Postgres from a model.** dbt only materializes into the DuckDB
  warehouse; `raw.*` and Postgres are read-only upstream. A model that targets Postgres
  violates the one invariant.

## Verify

```bash
cd transform

# 1. The graph parses and builds in dependency order (no cycles, no missing refs)
uv run dbt build --quiet

# 2. No gold/silver model reaches past its layer (static check)
#    gold may only ref silver_*; only bronze may source()/touch raw
! grep -rEl "ref\('bronze_" models/gold        # gold must not ref bronze
! grep -rEl "source\(|raw\." models/gold models/silver   # only bronze touches raw

# 3. Inspect the resolved DAG edges for any model
uv run dbt list --select gold_revenue_by_category+ --output path

# 4. Reconciliation proves no leak (from the gold-marts task eval):
#    sum(revenue) over the mart == sum(total_amount) over clean silver
```

The decisive proof is the task eval itself: if gold accidentally read bronze/raw, the
quarantined defect rows would push `sum(revenue)` above the clean silver source and
`eval_3` in `tasks/T-20260625-gold-marts.md` fails.

## See also

- `quick-reference.md` — this tech's index
- `reference/jinja-helpers.md` — exact `ref()` / `source()` signatures
- `reference/dbt-yaml-schema.md` — the `schema.yml` contract gold ships
- `concepts/models-and-materializations.md` — view-vs-table per layer (cited-TODO stub)
- `concepts/tests-and-sources.md` — declaring `raw.*` as sources + tests (cited-TODO stub)
